import Foundation
import Observation
import RadioCore

enum RadioConsultationSection: String, CaseIterable, Identifiable {
    case frequency = "Frecuencia"
    case repeaters = "Repetidoras"
    case callsigns = "Indicativos"
    case aprs = "APRS cercano"
    case satellites = "Satélites"
    var id: String { rawValue }
}

@MainActor @Observable final class RadioConsultationStore {
    var section: RadioConsultationSection = .frequency
    var frequencyMHz = "144.39"
    var chosenMode: RadioMode = .packet
    var repeaterSearch = ""
    var selectedRepeaterID: String?
    var repeaterLatitude = ""
    var repeaterLongitude = ""
    var repeaters: [VHFRepeater] = []
    var repeaterSourceDate = ""
    var repeaterFetchedAt: Date?
    var repeaterStatus = "El listado oficial de repetidoras se consulta en SUBTEL; conecta y pulsa Actualizar."
    var repeaterBusy = false
    var callsignSearch = ""
    var callsigns: [LicensedCallsign] = []
    var callsignSourceDate = ""
    var callsignFetchedAt: Date?
    var callsignStatus = "La búsqueda conserva solo indicativo, categoría, región y vencimiento; no guarda nombres."
    var callsignBusy = false
    private let subtel = SUBTELDataService()
    private var activated = false

    var filteredRepeaters: [VHFRepeater] {
        let query = repeaterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return repeaters }
        return repeaters.filter { "\($0.id) \($0.region) \($0.comuna) \($0.detail)".localizedCaseInsensitiveContains(query) }
    }
    var selectedRepeater: VHFRepeater? { repeaters.first(where: { $0.id == selectedRepeaterID }) }
    var matchingCallsigns: [LicensedCallsign] {
        let query = callsignSearch.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !query.isEmpty else { return [] }
        return callsigns.filter { $0.id.localizedCaseInsensitiveContains(query) }.prefix(150).map { $0 }
    }
    var matchedBands: [ChileBandAllocation] {
        guard let frequency = Self.parseFrequency(frequencyMHz), frequency > 0 else { return [] }
        return ChileBandAllocation.matches(frequency)
    }
    var selectedProfile: ReceptionProfile { chosenMode.receptionProfile }

    func activate() async {
        guard !activated else { return }; activated = true
        if let repeater = await subtel.cachedRepeaters() {
            repeaters = repeater.repeaters; repeaterSourceDate = repeater.sourceDate; repeaterFetchedAt = repeater.fetchedAt
            repeaterStatus = "Copia local de SUBTEL · \(repeaters.count) registros · \(repeater.sourceDate) · descargada \(repeater.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if let roster = await subtel.cachedCallsigns() {
            callsigns = roster.callsigns; callsignSourceDate = roster.sourceDate; callsignFetchedAt = roster.fetchedAt
            callsignStatus = "Copia local de SUBTEL · \(callsigns.count) indicativos · \(roster.sourceDate) · descargada \(roster.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if repeaterFetchedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true { Task { await self.refreshRepeaters() } }
        if callsignFetchedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true { Task { await self.refreshCallsigns() } }
    }

    func refreshRepeaters() async {
        guard !repeaterBusy else { return }; repeaterBusy = true; defer { repeaterBusy = false }
        repeaterStatus = "Consultando la página oficial de SUBTEL y actualizando el Excel…"
        do {
            let snapshot = try await subtel.refreshRepeaters()
            repeaters = snapshot.repeaters; repeaterSourceDate = snapshot.sourceDate; repeaterFetchedAt = snapshot.fetchedAt
            if !repeaters.contains(where: { $0.id == selectedRepeaterID }) { selectedRepeaterID = nil }
            repeaterStatus = "SUBTEL · \(repeaters.count) repetidoras · \(snapshot.sourceDate) · descargado \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            repeaterStatus = repeaters.isEmpty ? "No se pudo actualizar: \(error.localizedDescription)" : "Actualización fallida; se conserva la copia anterior. \(error.localizedDescription)"
        }
    }

    func refreshCallsigns() async {
        guard !callsignBusy else { return }; callsignBusy = true; defer { callsignBusy = false }
        callsignStatus = "Descargando los listados públicos y extrayendo solo campos de licencia…"
        do {
            let snapshot = try await subtel.refreshCallsigns()
            callsigns = snapshot.callsigns; callsignSourceDate = snapshot.sourceDate; callsignFetchedAt = snapshot.fetchedAt
            callsignStatus = "SUBTEL · \(callsigns.count) indicativos · \(snapshot.sourceDate) · descargado \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            callsignStatus = callsigns.isEmpty ? "No se pudo actualizar: \(error.localizedDescription)" : "Actualización fallida; se conserva la copia anterior. \(error.localizedDescription)"
        }
    }

    func chooseRepeater(_ repeater: VHFRepeater?) {
        selectedRepeaterID = repeater?.id
        repeaterLatitude = repeater?.latitude.map(Self.coordinateText) ?? ""
        repeaterLongitude = repeater?.longitude.map(Self.coordinateText) ?? ""
    }

    func makeSelectedRepeaterLocation() -> RadioLocation? { RadioLocation(latitude: repeaterLatitude, longitude: repeaterLongitude) }

    static func parseFrequency(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    static func coordinateText(_ value: Double) -> String { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value) }
}
