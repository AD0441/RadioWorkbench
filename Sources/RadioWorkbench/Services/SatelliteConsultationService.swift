import Foundation
import Observation
import RadioCore

struct AmateurSatellite: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let noradID: Int
    let orbit: TLEOrbit
    let transmitters: [AmateurSatelliteTransmitter]
    var id: Int { noradID }
    var downlinkSummary: String { transmitters.compactMap(\.downlink).filter { !$0.isEmpty }.joined(separator: " · ") }
    var uplinkSummary: String { transmitters.compactMap(\.uplink).filter { !$0.isEmpty }.joined(separator: " · ") }
    var downlinks: [SatelliteDownlink] {
        let values = transmitters.flatMap(SatelliteDownlink.options)
        return values.reduce(into: [SatelliteDownlink]()) { result, value in
            if !result.contains(where: { $0.id == value.id }) { result.append(value) }
        }
    }
    var modeSummary: String { Array(Set(transmitters.compactMap(\.mode).filter { !$0.isEmpty })).sorted().joined(separator: " · ") }
}

struct SatelliteCatalogSnapshot: Codable, Sendable {
    let satellites: [AmateurSatellite]
    let reports: [SatelliteStatusReport]
    let fetchedAt: Date
    let orbits: [TLEOrbit]?
    let frequencies: [AmateurSatelliteTransmitter]?
    let orbitSource: String?
    let orbitsFetchedAt: Date?
    let frequenciesFetchedAt: Date?
    let reportsFetchedAt: Date?
    let sourceErrors: [String: String]?
}

struct SatelliteStatusReport: Codable, Hashable, Sendable, Identifiable {
    let satelliteName: String
    let report: String
    let reportedAt: Date
    var id: String { "\(satelliteName)-\(report)-\(reportedAt.timeIntervalSince1970)" }
}

/// A transparent planning aid, not a calibrated chance of decoding or optical visibility.
struct SatelliteReceptionFactors: Hashable, Sendable {
    let elevationPoints: Int
    let elevationInWindow: Double
    let durationPoints: Int
    let orbitAgePoints: Int
    let usefulSeconds: TimeInterval
    let orbitAgeDays: Double
    var score: Int { elevationPoints + durationPoints + orbitAgePoints }
    init(pass: SatellitePass, orbit: TLEOrbit, observer: RadioLocation, window: DateInterval, now: Date) {
        let peakTime = min(window.end, max(window.start, pass.maximumAt))
        elevationInWindow = min(90, max(0, orbit.elevationDegrees(at: peakTime, latitude: observer.latitude, longitude: observer.longitude) ?? 0))
        usefulSeconds = pass.usefulDuration(in: window)
        orbitAgeDays = max(0, now.timeIntervalSince(orbit.epoch) / 86_400)
        elevationPoints = Int((elevationInWindow / 90 * 50).rounded())
        durationPoints = Int((min(600, usefulSeconds) / 600 * 30).rounded())
        orbitAgePoints = Int((max(0, 1 - abs(now.timeIntervalSince(orbit.epoch)) / (7 * 86_400)) * 20).rounded())
    }
    var explanation: String {
        "Elevación dentro de la ventana \(elevationPoints)/50 · tiempo dentro de la ventana \(durationPoints)/30 · actualidad orbital \(orbitAgePoints)/20. Equipo, actividad, ruido y obstáculos sin evaluar. No es una probabilidad de éxito."
    }
}

struct SatellitePassOpportunity: Identifiable, Sendable {
    let satelliteID: Int
    let satelliteName: String
    let pass: SatellitePass
    let downlinks: [SatelliteDownlink]
    let factors: SatelliteReceptionFactors
    let report: SatelliteStatusReport?
    var id: String { "\(satelliteID)-\(pass.id)" }
}

@MainActor @Observable final class SatelliteConsultationStore {
    var snapshot: SatelliteCatalogSnapshot?
    var selectedID: Int?
    var selectedDownlinkID: String?
    var passes: [SatellitePass] = []
    var selectedPassID: String?
    var observer: RadioLocation?
    var track: [SatelliteTrackSample] = []
    var nextHour: [SatellitePassOpportunity] = []
    var searchWindow: DateInterval?
    var searchObserver: RadioLocation?
    var minimumElevation = 5.0
    var onlyPublishedDownlinks = true
    private var passGeneration = UUID()
    private var passTask: Task<Void, Never>?
    private var passCalculation: Task<[SatellitePass], Never>?
    private var hourCalculation: Task<[SatellitePassOpportunity], Never>?
    var selectedPass: SatellitePass? { passes.first { $0.id == selectedPassID } }
    var selectedDownlink: SatelliteDownlink? {
        selected?.downlinks.first { $0.id == selectedDownlinkID } ?? selected?.downlinks.first
    }
    func selectPass(_ id: String?) {
        selectedPassID = id
        guard let pass = selectedPass, let satellite = selected, let observer else { track = []; return }
        track = SatellitePassPredictor.track(orbit: satellite.orbit, pass: pass, observer: observer)
    }
    private func cancelCalculations() {
        passGeneration = UUID(); passTask?.cancel(); passTask = nil
        passCalculation?.cancel(); passCalculation = nil; hourCalculation?.cancel(); hourCalculation = nil
        calculatingPasses = false
    }
    func clearPasses() {
        cancelCalculations()
        passes = []; selectedPassID = nil; track = []; observer = nil
        nextHour = []; searchWindow = nil; searchObserver = nil
    }
    func cancelPassSearch() { clearPasses(); status = "Búsqueda cancelada." }
    var status = "Frecuencias de AMSAT y elementos orbitales de CelesTrak; actualiza antes de planificar un pase."
    var busy = false
    var calculatingPasses = false
    private let service = SatelliteCatalogService()
    private var activated = false

    var selected: AmateurSatellite? { snapshot?.satellites.first(where: { $0.id == selectedID }) }
    var latestStatus: SatelliteStatusReport? { selected.flatMap { latestStatus(for: $0, now: Date()) } }
    func latestStatus(for satellite: AmateurSatellite, now: Date) -> SatelliteStatusReport? {
        Self.latestStatus(for: satellite, reports: snapshot?.reports ?? [], now: now)
    }
    nonisolated static func latestStatus(for satellite: AmateurSatellite, reports: [SatelliteStatusReport], now: Date) -> SatelliteStatusReport? {
        let aliases = SatelliteCatalogService.nameAliases(satellite.name).union(satellite.transmitters.flatMap { SatelliteCatalogService.nameAliases($0.name) })
        return SatelliteCatalogService.recentReports(reports, now: now)
            .filter { !aliases.isDisjoint(with: SatelliteCatalogService.nameAliases($0.satelliteName)) }
            .max(by: { $0.reportedAt < $1.reportedAt })
    }

    func selectSatellite(_ id: Int?) {
        guard selectedID != id else { return }
        selectedID = id; selectedDownlinkID = nil; clearPasses()
    }
    func showOpportunity(_ opportunity: SatellitePassOpportunity) {
        guard let searchObserver else { return }
        cancelCalculations()
        selectedID = opportunity.satelliteID; selectedDownlinkID = opportunity.downlinks.first?.id
        observer = searchObserver; passes = [opportunity.pass]; selectPass(opportunity.pass.id)
    }

    func activate() async {
        guard !activated else { return }; activated = true
        snapshot = await service.cached()
        if selectedID == nil { selectedID = snapshot?.satellites.first(where: { $0.name.localizedCaseInsensitiveContains("ISS") })?.id ?? snapshot?.satellites.first?.id }
        if snapshot == nil { status = "Conéctate y actualiza el catálogo de frecuencias y órbitas." }
        if snapshot.map({ Date().timeIntervalSince($0.fetchedAt) > 21_600 || $0.satellites.contains(where: { !$0.orbit.propagationReady }) || !($0.sourceErrors ?? [:]).isEmpty }) ?? true { Task { await self.refresh() } }
    }

    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        status = "Actualizando frecuencias de satélites y elementos orbitales…"
        do {
            snapshot = try await service.refresh()
            clearPasses()
            if selectedID == nil || snapshot?.satellites.contains(where: { $0.id == selectedID }) != true {
                selectedID = snapshot?.satellites.first(where: { $0.name.localizedCaseInsensitiveContains("ISS") })?.id ?? snapshot?.satellites.first?.id
                selectedDownlinkID = nil
            }
            let count = snapshot?.satellites.count ?? 0
            let errors = snapshot?.sourceErrors ?? [:]
            status = "\(count) satélites · órbitas \(snapshot?.orbitSource ?? "copia local") · actualización por fuente."
            if !errors.isEmpty { status += " Avisos: " + errors.keys.sorted().map { "\($0): \(errors[$0]!)" }.joined(separator: " · ") }
        } catch {
            status = snapshot == nil ? "No se pudo actualizar el catálogo: \(error.localizedDescription)" : "Se conserva la última copia; actualización fallida: \(error.localizedDescription)"
        }
    }

    func calculatePasses(location: RadioLocation?, now: Date = Date()) {
        guard let location, let satellite = selected else { status = "Selecciona una ubicación guardada y un satélite para calcular sus pases."; return }
        guard satellite.orbit.propagationReady else { status = "Esta copia orbital antigua no conserva BSTAR. Pulsa Actualizar antes de calcular con SGP4."; return }
        clearPasses(); calculatingPasses = true; observer = location
        let orbit = satellite.orbit, token = passGeneration, id = satellite.id, minimum = minimumElevation
        let calculation = Task.detached(priority: .userInitiated) {
            SatellitePassPredictor.passes(orbit: orbit, latitude: location.latitude, longitude: location.longitude,
                from: now, hours: 48, stepSeconds: 30, minimumPeak: minimum)
        }
        passCalculation = calculation
        passTask = Task { [weak self] in
            let result = await withTaskCancellationHandler { await calculation.value } onCancel: { calculation.cancel() }
            guard let self, !Task.isCancelled, self.passGeneration == token, self.selectedID == id else { return }
            self.passes = result; self.calculatingPasses = false; self.passTask = nil; self.passCalculation = nil
            self.selectPass(result.first?.id)
            self.status = result.isEmpty ? "Sin pases con máximo ≥\(Int(minimum))° en 48 h; verifica ubicación y época orbital." : "\(result.count) pases en 48 h · mapa y trayectoria en el cielo · SGP4/SDP4 y WGS84."
        }
    }

    func searchNextHour(location: RadioLocation?, now: Date = Date()) {
        guard let location, let snapshot else { status = "Guarda tu ubicación y actualiza el catálogo antes de buscar pases."; return }
        clearPasses(); calculatingPasses = true
        let window = DateInterval(start: now, duration: 3600), token = passGeneration, minimum = minimumElevation
        searchWindow = window; searchObserver = location
        let eligible = snapshot.satellites.filter { $0.orbit.propagationReady && (!onlyPublishedDownlinks || !$0.downlinks.isEmpty) }
        let candidates = Array(eligible.prefix(512)), reports = snapshot.reports
        status = "Buscando pases de \(candidates.count) satélites durante los próximos 60 minutos…"
        let calculation = Task.detached(priority: .userInitiated) {
            Self.opportunities(satellites: candidates, reports: reports, observer: location, window: window, minimumPeak: minimum)
        }
        hourCalculation = calculation
        passTask = Task { [weak self] in
            let result = await withTaskCancellationHandler { await calculation.value } onCancel: { calculation.cancel() }
            guard let self, !Task.isCancelled, self.passGeneration == token else { return }
            self.nextHour = result; self.calculatingPasses = false; self.passTask = nil; self.hourCalculation = nil
            self.status = "\(result.count) pases RF en la próxima hora · \(candidates.count) satélites revisados · horizonte geométrico ideal, máximo ≥\(Int(minimum))°."
            if eligible.count > candidates.count { self.status += " Catálogo limitado a 512 satélites por búsqueda." }
            if let first = result.first { self.showOpportunity(first) }
        }
    }

    nonisolated static func opportunities(satellites: [AmateurSatellite], reports: [SatelliteStatusReport], observer: RadioLocation,
                                          window: DateInterval, minimumPeak: Double) -> [SatellitePassOpportunity] {
        var result: [SatellitePassOpportunity] = []
        for satellite in satellites.prefix(512) {
            if Task.isCancelled { return [] }
            for pass in SatellitePassPredictor.passes(orbit: satellite.orbit, latitude: observer.latitude, longitude: observer.longitude,
                                                       window: window, stepSeconds: 20, minimumPeak: minimumPeak) {
                result.append(SatellitePassOpportunity(satelliteID: satellite.id, satelliteName: satellite.name, pass: pass,
                    downlinks: satellite.downlinks, factors: SatelliteReceptionFactors(pass: pass, orbit: satellite.orbit, observer: observer, window: window, now: window.start),
                    report: latestStatus(for: satellite, reports: reports, now: window.start)))
            }
        }
        return result.sorted { max($0.pass.aos, window.start) < max($1.pass.aos, window.start) }
    }
}
