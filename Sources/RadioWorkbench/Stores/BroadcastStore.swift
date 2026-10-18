import AppKit
import Observation
import RadioCore

@MainActor @Observable final class BroadcastStore {
    var snapshot: BroadcastSnapshot?
    var hfccSnapshot: HFCCScheduleSnapshot?
    var hfccStatus = "HFCC complementa EiBi con datos declarados de potencia, zona y rumbo."
    var busy = false
    var status = "Con conexión, EiBi se actualiza al abrir la guía y cada 6 horas."
    var search = ""
    var band = "Todas"
    var language = "Todos"
    var category = "Todas"
    var onlyNow = true
    var onlyFavorites = false
    var frequency = ""
    var tolerance = 5.0
    var selectedID: String? {
        didSet { if let selectedID { retainedSelectionID = selectedID } }
    }
    private var retainedSelectionID: String?
    var selectedEntry: BroadcastEntry? {
        guard let id = selectedID ?? retainedSelectionID else { return nil }
        return snapshot?.entries.first { $0.id == id }
    }
    var favorites: Set<String>
    var alertFavorites: Set<String>
    var alertLeadMinutes: Int
    var alertStatus = "Activa avisos en el detalle de una emisora favorita."
    var latitude: String
    var longitude: String
    private let service = BroadcastService()
    private let hfccService = HFCCScheduleService()
    private let alertScheduler = BroadcastAlertScheduler()
    @ObservationIgnored private var hfccByRoundedFrequency: [Int: [HFCCTransmission]] = [:]
    private var activated = false
    private var lastAttempt: Date?
    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "broadcastFavorites") ?? [])
        alertFavorites = Set(UserDefaults.standard.stringArray(forKey: "broadcastAlertFavorites") ?? [])
        let savedLead = UserDefaults.standard.integer(forKey: "broadcastAlertLeadMinutes")
        alertLeadMinutes = [0, 5, 10, 15].contains(savedLead) ? savedLead : 10
        latitude = UserDefaults.standard.string(forKey: "listenerLatitude") ?? ""
        longitude = UserDefaults.standard.string(forKey: "listenerLongitude") ?? ""
    }
    func activate() async {
        guard !activated else { return }
        activated = true
        snapshot = await service.cached()
        hfccSnapshot = await hfccService.cached()
        rebuildHFCCIndex()
        if snapshot != nil { status = "Última copia disponible. Comprobando actualizaciones…" }
        await refresh()
    }
    func runAutoRefresh() async {
        await activate()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            await refreshIfDue()
        }
    }
    func refreshIfDue() async {
        if activated, !busy, lastAttempt.map({ Date().timeIntervalSince($0) >= 6 * 3600 }) ?? true { await refresh() }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true; lastAttempt = Date(); status = "Consultando EiBi y HFCC…"
        defer { busy = false }
        async let eibiTask = service.download()
        async let hfccTask = hfccService.download()
        do {
            snapshot = try await eibiTask
            status = "Datos recibidos de EiBi. Próxima comprobación automática en 6 horas."
        } catch {
            status = snapshot == nil ? "EiBi no se pudo actualizar: \(error.localizedDescription). Puedes reintentar o importar un CSV." : "EiBi conserva su copia anterior: \(error.localizedDescription)."
            // Retry a failed connection on the next minute tick, capped at five minutes.
            lastAttempt = Date().addingTimeInterval(-6 * 3600 + 5 * 60)
        }
        do {
            hfccSnapshot = try await hfccTask
            rebuildHFCCIndex()
            if let hfccSnapshot { hfccStatus = "HFCC · \(hfccSnapshot.season.uppercased()) · \(hfccSnapshot.transmissions.count) transmisiones · potencia declarada, no medida." }
        } catch {
            hfccStatus = hfccSnapshot == nil ? "HFCC no disponible: \(error.localizedDescription). EiBi sigue funcionando." : "HFCC conserva la copia anterior: \(error.localizedDescription)."
        }
        await rescheduleAlerts()
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, .plainText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { snapshot = try await service.importCSV(url); status = "CSV importado. Actualizar consultará la temporada vigente en EiBi."; await rescheduleAlerts() }
            catch { status = "No se pudo importar: \(error.localizedDescription)" }
        }
    }
    func toggleFavorite(_ entry: BroadcastEntry) {
        if favorites.contains(entry.id) { favorites.remove(entry.id) } else { favorites.insert(entry.id) }
        if !favorites.contains(entry.id) {
            alertFavorites.remove(entry.id)
            UserDefaults.standard.set(Array(alertFavorites), forKey: "broadcastAlertFavorites")
        }
        UserDefaults.standard.set(Array(favorites), forKey: "broadcastFavorites")
        Task { await rescheduleAlerts() }
    }
    func setFavoriteAlert(_ entry: BroadcastEntry, enabled: Bool) {
        if enabled {
            guard favorites.contains(entry.id) else { alertStatus = "Guarda primero la emisora en Favoritas."; return }
            Task {
                do {
                    guard try await alertScheduler.requestAuthorization() else {
                        alertStatus = "macOS no autorizó las notificaciones. Revísalo en Ajustes del Sistema."
                        return
                    }
                    alertFavorites.insert(entry.id)
                    UserDefaults.standard.set(Array(alertFavorites), forKey: "broadcastAlertFavorites")
                    await rescheduleAlerts()
                } catch { alertStatus = "No se pudieron activar las notificaciones: \(error.localizedDescription)" }
            }
        } else {
            alertFavorites.remove(entry.id)
            UserDefaults.standard.set(Array(alertFavorites), forKey: "broadcastAlertFavorites")
            Task { await rescheduleAlerts() }
        }
    }
    func setAlertLeadMinutes(_ value: Int) {
        guard [0, 5, 10, 15].contains(value) else { return }
        alertLeadMinutes = value
        UserDefaults.standard.set(value, forKey: "broadcastAlertLeadMinutes")
        Task { await rescheduleAlerts() }
    }
    func rescheduleAlerts() async {
        let entries = snapshot?.entries.filter { alertFavorites.contains($0.id) } ?? []
        do {
            let count = try await alertScheduler.schedule(entries: entries, leadMinutes: alertLeadMinutes)
            alertStatus = alertFavorites.isEmpty
                ? "Activa avisos en el detalle de una emisora favorita."
                : "\(count) próximos avisos programados · \(alertLeadMinutes) min de anticipación · horario UTC."
        } catch { alertStatus = "No se pudieron programar avisos: \(error.localizedDescription)" }
    }
    func saveLocation() {
        UserDefaults.standard.set(latitude, forKey: "listenerLatitude"); UserDefaults.standard.set(longitude, forKey: "listenerLongitude")
    }
    var position: (Double,Double)? {
        guard let value = RadioLocation(latitude: latitude, longitude: longitude) else { return nil }
        return (value.latitude, value.longitude)
    }
    var invalidFrequency: Bool {
        guard !frequency.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let value = Double(frequency.replacingOccurrences(of: ",", with: ".")) else { return true }
        return !value.isFinite || value <= 0
    }
    func results(at date: Date) -> [BroadcastEntry] {
        guard let snapshot else { return [] }
        if invalidFrequency { return [] }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let freq = Double(frequency.replacingOccurrences(of: ",", with: "."))
        return snapshot.entries.filter { e in
            if onlyNow && BroadcastCalendar.activity(e, at: date, season: snapshot.season) != .scheduled && BroadcastCalendar.activity(e, at: date, season: snapshot.season) != .uncertain { return false }
            if onlyFavorites && !favorites.contains(e.id) { return false }
            if band != "Todas" && band != e.band && band != e.broadcastBand { return false }
            if language != "Todos" && e.language != language { return false }
            if category == "Radiodifusión" && e.isUtility { return false }
            if category == "Utilitarias" && !e.isUtility { return false }
            if let freq, abs(e.frequencyKHz-freq) > tolerance { return false }
            if !q.isEmpty {
                let haystack = "\(e.station) \(e.country) \(snapshot.reference.countries[e.country] ?? "") \(e.target) \(e.language) \(snapshot.reference.languages[e.language] ?? "")"
                if !haystack.localizedCaseInsensitiveContains(q) { return false }
            }
            return true
        }.sorted { $0.frequencyKHz == $1.frequencyKHz ? $0.station < $1.station : $0.frequencyKHz < $1.frequencyKHz }
    }
    func hfccMatch(for entry: BroadcastEntry) -> HFCCTransmission? {
        guard let hfccSnapshot else { return nil }
        let frequency = Int(entry.frequencyKHz.rounded())
        let candidates = (-1...1).flatMap { hfccByRoundedFrequency[frequency + $0] ?? [] }
        return hfccSnapshot.match(for: entry, candidates: candidates)
    }
    func hfccMatches(for entries: [BroadcastEntry]) -> [String: HFCCTransmission] {
        var matches: [String: HFCCTransmission] = [:]
        for entry in entries { if let transmission = hfccMatch(for: entry) { matches[entry.id] = transmission } }
        return matches
    }
    private func rebuildHFCCIndex() {
        hfccByRoundedFrequency = Dictionary(grouping: hfccSnapshot?.transmissions ?? []) { Int($0.frequencyKHz.rounded()) }
    }
}
