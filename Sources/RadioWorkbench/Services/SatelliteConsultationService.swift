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

@MainActor @Observable final class SatelliteConsultationStore {
    var snapshot: SatelliteCatalogSnapshot?
    var selectedID: Int?
    var passes: [SatellitePass] = []
    var selectedPassID: String?
    var observer: RadioLocation?
    var track: [SatelliteTrackSample] = []
    private var passGeneration = UUID()
    private var passTask: Task<Void, Never>?
    var selectedPass: SatellitePass? { passes.first { $0.id == selectedPassID } }
    func selectPass(_ id: String?) {
        selectedPassID = id
        guard let pass = selectedPass, let satellite = selected, let observer else { track = []; return }
        track = SatellitePassPredictor.track(orbit: satellite.orbit, pass: pass, observer: observer)
    }
    func clearPasses() {
        passGeneration = UUID(); passTask?.cancel(); passTask = nil
        passes = []; selectedPassID = nil; track = []; observer = nil; calculatingPasses = false
    }
    var status = "Frecuencias de AMSAT y elementos orbitales de CelesTrak; actualiza antes de planificar un pase."
    var busy = false
    var calculatingPasses = false
    private let service = SatelliteCatalogService()
    private var activated = false

    var selected: AmateurSatellite? { snapshot?.satellites.first(where: { $0.id == selectedID }) }
    var latestStatus: SatelliteStatusReport? {
        guard let selected else { return nil }
        let aliases = SatelliteCatalogService.nameAliases(selected.name).union(selected.transmitters.flatMap { SatelliteCatalogService.nameAliases($0.name) })
        return snapshot?.reports.filter { !aliases.isDisjoint(with: SatelliteCatalogService.nameAliases($0.satelliteName)) }
            .max(by: { $0.reportedAt < $1.reportedAt })
    }

    func selectSatellite(_ id: Int?) {
        guard selectedID != id else { return }
        selectedID = id; clearPasses()
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
            }
            let count = snapshot?.satellites.count ?? 0
            let errors = snapshot?.sourceErrors ?? [:]
            status = "\(count) satélites · órbitas \(snapshot?.orbitSource ?? "copia local") · actualización por fuente."
            if !errors.isEmpty { status += " Avisos: " + errors.keys.sorted().map { "\($0): \(errors[$0]!)" }.joined(separator: " · ") }
        } catch {
            status = snapshot == nil ? "No se pudo actualizar el catálogo: \(error.localizedDescription)" : "Se conserva la última copia; actualización fallida: \(error.localizedDescription)"
        }
    }

    func calculatePasses(location: RadioLocation?) {
        guard let location, let satellite = selected else { status = "Selecciona una ubicación guardada y un satélite para calcular sus pases."; return }
        guard satellite.orbit.propagationReady else { status = "Esta copia orbital antigua no conserva BSTAR. Pulsa Actualizar antes de calcular con SGP4."; return }
        clearPasses(); calculatingPasses = true; observer = location
        let orbit = satellite.orbit, token = passGeneration, id = satellite.id
        let calculation = Task.detached(priority: .userInitiated) {
            SatellitePassPredictor.passes(orbit: orbit, latitude: location.latitude, longitude: location.longitude,
                from: Date(), hours: 48, stepSeconds: 30, minimumPeak: 5)
        }
        passTask = Task { [weak self] in
            let result = await calculation.value
            guard let self, !Task.isCancelled, self.passGeneration == token, self.selectedID == id else { return }
            self.passes = result; self.calculatingPasses = false; self.passTask = nil
            self.selectPass(result.first?.id)
            self.status = result.isEmpty ? "Sin pases con máximo ≥5° en 48 h; verifica ubicación y época orbital." : "\(result.count) pases en 48 h · selecciona una fila para ver mapa y trayectoria en el cielo · SGP4/SDP4 y WGS84."
        }
    }
}
