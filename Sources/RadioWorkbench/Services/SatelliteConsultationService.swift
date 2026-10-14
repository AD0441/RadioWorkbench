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
    var status = "Frecuencias de AMSAT y elementos orbitales de CelesTrak; actualiza antes de planificar un pase."
    var busy = false
    var calculatingPasses = false
    private let service = SatelliteCatalogService()
    private var activated = false

    var selected: AmateurSatellite? { snapshot?.satellites.first(where: { $0.id == selectedID }) }
    var latestStatus: SatelliteStatusReport? {
        guard let selected else { return nil }
        return snapshot?.reports.filter { $0.satelliteName.caseInsensitiveCompare(selected.name) == .orderedSame }
            .max(by: { $0.reportedAt < $1.reportedAt })
    }

    func selectSatellite(_ id: Int?) {
        guard selectedID != id else { return }
        selectedID = id; passes = []
    }

    func activate() async {
        guard !activated else { return }; activated = true
        snapshot = await service.cached()
        if selectedID == nil { selectedID = snapshot?.satellites.first(where: { $0.name.localizedCaseInsensitiveContains("ISS") })?.id ?? snapshot?.satellites.first?.id }
        if snapshot == nil { status = "Conéctate y actualiza el catálogo de frecuencias y órbitas." }
        if snapshot.map({ Date().timeIntervalSince($0.fetchedAt) > 21_600 }) ?? true { Task { await self.refresh() } }
    }

    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        status = "Actualizando frecuencias de satélites y elementos orbitales…"
        do {
            snapshot = try await service.refresh()
            if selectedID == nil || snapshot?.satellites.contains(where: { $0.id == selectedID }) != true {
                selectedID = snapshot?.satellites.first(where: { $0.name.localizedCaseInsensitiveContains("ISS") })?.id ?? snapshot?.satellites.first?.id
            }
            let count = snapshot?.satellites.count ?? 0
            status = "\(count) satélites con frecuencias y órbita coincidentes · fuentes actualizadas \(snapshot?.fetchedAt.formatted(date: .abbreviated, time: .shortened) ?? "") · catálogo AMSAT/SatNOGS + TLE CelesTrak."
        } catch {
            status = snapshot == nil ? "No se pudo actualizar el catálogo: \(error.localizedDescription)" : "Se conserva la última copia; actualización fallida: \(error.localizedDescription)"
        }
    }

    func calculatePasses(location: RadioLocation?) {
        guard let location, let satellite = selected else { status = "Selecciona una ubicación guardada y un satélite para calcular sus pases."; return }
        calculatingPasses = true; passes = []
        let orbit = satellite.orbit
        let id = satellite.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = SatellitePassPredictor.passes(orbit: orbit, latitude: location.latitude, longitude: location.longitude,
                                                       from: Date(), hours: 48, stepSeconds: 30, minimumPeak: 5)
            await MainActor.run {
                guard let self, self.selectedID == id else { return }
                self.passes = result
                self.calculatingPasses = false
                self.status = result.isEmpty ? "Sin pases con elevación máxima ≥5° en las próximas 48 h; prueba otro satélite o verifica ubicación y elementos orbitales." : "\(result.count) pases geométricos en 48 h · Kepler + corrección secular J2, no SGP4. Usa AOS/LOS como orientación y comprueba Doppler en recepción."
            }
        }
    }
}

private actor SatelliteCatalogService {
    private let cacheURL: URL
    private let transport: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private static let celestrakURL = URL(string: "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=JSON")!
    private static let frequenciesURL = URL(string: "https://raw.githubusercontent.com/palewire/amateur-satellite-database/main/data/amsat-active-frequencies.json")!
    private static let statusesURL = URL(string: "https://www.amsat.org/status/api/v1/reports.php?hours=72&limit=500")!

    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }) {
        cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true).appendingPathComponent("amateur-satellites.json")
        self.transport = transport
    }

    func cached() -> SatelliteCatalogSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 12_000_000 else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SatelliteCatalogSnapshot.self, from: data)
    }

    func refresh(now: Date = Date()) async throws -> SatelliteCatalogSnapshot {
        var tleRequest = URLRequest(url: Self.celestrakURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        tleRequest.setValue("RadioWorkbench/0.8.9 (amateur satellite pass lookup)", forHTTPHeaderField: "User-Agent")
        var frequenciesRequest = URLRequest(url: Self.frequenciesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        frequenciesRequest.setValue("RadioWorkbench/0.8.9 (amateur satellite receive catalog)", forHTTPHeaderField: "User-Agent")
        var statusesRequest = URLRequest(url: Self.statusesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        statusesRequest.setValue("RadioWorkbench/0.8.9 (amateur satellite status lookup)", forHTTPHeaderField: "User-Agent")
        async let tleResponse = transport(tleRequest)
        async let frequenciesResponse = transport(frequenciesRequest)
        async let statusesResponse = try? transport(statusesRequest)
        let (tleData, frequencyData) = try await (tleResponse, frequenciesResponse)
        guard tleData.1.statusCode == 200, tleData.1.url?.scheme == "https", tleData.1.url?.host == "celestrak.org", tleData.0.count <= 8_000_000,
              frequencyData.1.statusCode == 200, frequencyData.1.url?.scheme == "https", frequencyData.1.url?.host == "raw.githubusercontent.com", frequencyData.0.count <= 4_000_000 else { throw URLError(.badServerResponse) }
        let ommRecords = try JSONSerialization.jsonObject(with: tleData.0) as? [[String: Any]] ?? []
        let frequencyRecords = try JSONDecoder().decode([AmateurSatelliteTransmitter].self, from: frequencyData.0)
        let groups = Dictionary(grouping: frequencyRecords.compactMap { entry -> (Int, AmateurSatelliteTransmitter)? in
            guard let id = entry.noradID.flatMap(Int.init) else { return nil }; return (id, entry)
        }, by: \.0)
        let satellites = ommRecords.compactMap { Self.parseOrbit($0) }.compactMap { orbit -> AmateurSatellite? in
            guard let transmitters = groups[orbit.catalogNumber]?.map(\.1), !transmitters.isEmpty else { return nil }
            return AmateurSatellite(name: orbit.name, noradID: orbit.catalogNumber, orbit: orbit, transmitters: transmitters)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard satellites.count >= 5 else { throw DataError.incompleteCatalog }
        let statusResponse = await statusesResponse
        let reports: [SatelliteStatusReport]
        if let (data, response) = statusResponse, response.statusCode == 200, response.url?.scheme == "https",
           response.url?.host == "www.amsat.org", data.count <= 3_000_000 {
            reports = Self.parseReports(data)
        } else { reports = [] }
        let result = SatelliteCatalogSnapshot(satellites: satellites, reports: reports, fetchedAt: now)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: cacheURL, options: .atomic)
        return result
    }

    private static func parseOrbit(_ json: [String: Any]) -> TLEOrbit? {
        func number(_ keys: String...) -> Double? {
            for key in keys {
                if let value = json[key] as? NSNumber { return value.doubleValue }
                if let value = json[key] as? String, let number = Double(value) { return number }
            }
            return nil
        }
        guard let name = (json["OBJECT_NAME"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let catalogNumber = number("NORAD_CAT_ID"),
              let meanMotion = number("MEAN_MOTION"), let eccentricity = number("ECCENTRICITY"),
              let inclination = number("INCLINATION"), let raan = number("RA_OF_ASC_NODE"),
              let argument = number("ARG_OF_PERICENTER"), let anomaly = number("MEAN_ANOMALY"),
              let epochText = json["EPOCH"] as? String, let epoch = parseDate(epochText) else { return nil }
        return TLEOrbit(name: name, catalogNumber: Int(catalogNumber), epoch: epoch, meanMotionRevolutionsPerDay: meanMotion,
                        eccentricity: eccentricity, inclinationDegrees: inclination, raanDegrees: raan,
                        argumentOfPerigeeDegrees: argument, meanAnomalyDegrees: anomaly)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func parseReports(_ data: Data) -> [SatelliteStatusReport] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let report = (row["report"] as? String ?? row["status"] as? String)?.trimmingCharacters(in: .whitespaces),
                  let dateText = row["reported_at"] as? String ?? row["reportedAt"] as? String,
                  let date = parseDate(dateText) else { return nil }
            return SatelliteStatusReport(satelliteName: name, report: report, reportedAt: date)
        }.sorted { $0.reportedAt > $1.reportedAt }
    }

    private enum DataError: Error { case incompleteCatalog }
}
