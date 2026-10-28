import Foundation
import RadioCore

actor SatelliteCatalogService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let celestrakURL = URL(string: "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=JSON")!
    static let amsatOrbitURL = URL(string: "https://www.amsat.org/tle/current/nasabare.txt")!
    static let frequenciesURL = URL(string: "https://api.github.com/repos/palewire/amateur-satellite-database/contents/data/amsat-active-frequencies.json?ref=main")!
    static let rawFrequenciesURL = URL(string: "https://raw.githubusercontent.com/palewire/amateur-satellite-database/main/data/amsat-active-frequencies.json")!
    static let statusesURL = URL(string: "https://www.amsat.org/status/api/v1/reports.php?hours=72&limit=500")!
    private let cacheURL: URL
    private let transport: Transport
    init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench/amateur-satellites.json")
        self.transport = transport
    }
    func cached() -> SatelliteCatalogSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 12_000_000 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self), let date = SatelliteElementParser.utcDate(text) { return date }
            let seconds = try value.decode(Double.self)
            guard seconds.isFinite else { throw SatelliteElementError.invalidData }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return try? decoder.decode(SatelliteCatalogSnapshot.self, from: data)
    }
    private struct Attempt<T: Sendable>: Sendable {
        let value: T?
        let source: String?
        let error: String?
    }
    private func fetch(_ url: URL, maximumBytes: Int, rawGitHub: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("RadioWorkbench/0.12.0 (receive-only satellite planning)", forHTTPHeaderField: "User-Agent")
        if rawGitHub { request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept") }
        let (data, response) = try await transport(request)
        guard response.statusCode == 200 else { throw CatalogError.http(url.host ?? "fuente", response.statusCode) }
        guard response.url?.scheme == "https", response.url?.host == url.host, !data.isEmpty, data.count <= maximumBytes else { throw CatalogError.invalidResponse(url.host ?? "fuente") }
        return data
    }
    private func loadOrbits(preferred: String?) async -> Attempt<[TLEOrbit]> {
        var failures: [String] = []
        var sources = [(Self.celestrakURL, "CelesTrak GP"), (Self.amsatOrbitURL, "AMSAT TLE")]
        if preferred == "AMSAT TLE" { sources.reverse() }
        for (url, source) in sources {
            do {
                let data = try await fetch(url, maximumBytes: 8_000_000)
                let values = try url == Self.celestrakURL ? SatelliteElementParser.omm(data) : SatelliteElementParser.tle(data)
                guard values.count >= 5, values.allSatisfy(\.propagationReady) else { throw SatelliteElementError.invalidData }
                return Attempt(value: values, source: source, error: failures.isEmpty ? nil : failures.joined(separator: "; "))
            } catch { failures.append("\(source): \(error.localizedDescription)") }
        }
        return Attempt(value: nil, source: nil, error: failures.joined(separator: "; "))
    }
    private func loadFrequencies() async -> Attempt<[AmateurSatelliteTransmitter]> {
        var failures: [String] = []
        for url in [Self.frequenciesURL, Self.rawFrequenciesURL] {
            do {
                var data = try await fetch(url, maximumBytes: 4_000_000, rawGitHub: url == Self.frequenciesURL)
                // GitHub can return the Contents envelope if a proxy removes the Accept header.
                if let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   envelope["encoding"] as? String == "base64", let content = envelope["content"] as? String,
                   let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters), decoded.count <= 4_000_000 { data = decoded }
                let values = try JSONDecoder().decode([AmateurSatelliteTransmitter].self, from: data)
                guard values.count >= 5 else { throw CatalogError.invalidResponse("frecuencias") }
                return Attempt(value: values, source: "AMSAT/SatNOGS", error: nil)
            } catch { failures.append("\(url.host ?? "fuente"): \(error.localizedDescription)") }
        }
        return Attempt(value: nil, source: nil, error: failures.joined(separator: "; "))
    }
    private func loadReports(now: Date) async -> Attempt<[SatelliteStatusReport]> {
        do {
            let data = try await fetch(Self.statusesURL, maximumBytes: 3_000_000)
            return Attempt(value: try Self.parseReports(data, now: now), source: "AMSAT", error: nil)
        } catch { return Attempt(value: nil, source: nil, error: error.localizedDescription) }
    }
    func refresh(now: Date = Date()) async throws -> SatelliteCatalogSnapshot {
        let previous = cached()
        async let orbitRequest = loadOrbits(preferred: previous?.orbitSource)
        async let frequencyRequest = loadFrequencies()
        async let reportRequest = loadReports(now: now)
        let (orbitAttempt, frequencyAttempt, reportAttempt) = await (orbitRequest, frequencyRequest, reportRequest)
        let orbits = orbitAttempt.value ?? previous?.orbits ?? previous?.satellites.map(\.orbit) ?? []
        let frequencies = frequencyAttempt.value ?? previous?.frequencies ?? previous?.satellites.flatMap(\.transmitters) ?? []
        let reports = reportAttempt.value ?? previous?.reports ?? []
        var errors: [String: String] = [:]
        if let error = orbitAttempt.error { errors["Órbitas"] = error }
        if let error = frequencyAttempt.error { errors["Frecuencias"] = error }
        if let error = reportAttempt.error { errors["Reportes"] = error }
        guard !orbits.isEmpty else { throw CatalogError.noOrbits(errors["Órbitas"] ?? "Sin datos válidos ni copia local.") }
        let groups = Dictionary(grouping: frequencies.compactMap { entry -> (Int, AmateurSatelliteTransmitter)? in
            guard let id = entry.noradID.flatMap(SatelliteElementParser.catalogNumber) else { return nil }; return (id, entry)
        }, by: \.0)
        let unique = Dictionary(orbits.map { ($0.catalogNumber, $0) }, uniquingKeysWith: { $0.epoch >= $1.epoch ? $0 : $1 })
        let satellites = unique.values.map { orbit in AmateurSatellite(name: orbit.name, noradID: orbit.catalogNumber,
            orbit: orbit, transmitters: groups[orbit.catalogNumber]?.map(\.1) ?? []) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        func snapshot(_ issues: [String: String]) -> SatelliteCatalogSnapshot {
            SatelliteCatalogSnapshot(satellites: satellites, reports: reports, fetchedAt: now, orbits: orbits, frequencies: frequencies,
                orbitSource: orbitAttempt.source ?? previous?.orbitSource ?? "copia local",
                orbitsFetchedAt: orbitAttempt.value == nil ? previous?.orbitsFetchedAt ?? previous?.fetchedAt : now,
                frequenciesFetchedAt: frequencyAttempt.value == nil ? previous?.frequenciesFetchedAt : now,
                reportsFetchedAt: reportAttempt.value == nil ? previous?.reportsFetchedAt : now, sourceErrors: issues)
        }
        let result = snapshot(errors)
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Date's numeric reference-time encoding preserves orbital epoch fractions exactly.
            let encoder = JSONEncoder()
            try encoder.encode(result).write(to: cacheURL, options: .atomic)
        } catch { errors["Caché local"] = error.localizedDescription }
        return errors == result.sourceErrors ? result : snapshot(errors)
    }
    nonisolated static func recentReports(_ reports: [SatelliteStatusReport], now: Date) -> [SatelliteStatusReport] {
        reports.filter { (-300...72 * 3_600).contains(now.timeIntervalSince($0.reportedAt)) }
    }
    static func parseReports(_ data: Data, now: Date) throws -> [SatelliteStatusReport] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = root["data"] as? [[String: Any]] else { throw CatalogError.invalidResponse("reportes AMSAT") }
        return rows.compactMap { row in
            guard let name = row["satellite_display_name"] as? String ?? row["name"] as? String, !name.isEmpty, name.count <= 200,
                let report = row["report"] as? String ?? row["status"] as? String, !report.isEmpty, report.count <= 200,
                let dateText = row["reported_time"] as? String ?? row["reported_at"] as? String ?? row["reportedAt"] as? String,
                let date = SatelliteElementParser.utcDate(dateText), (-300...72 * 3_600).contains(now.timeIntervalSince(date)) else { return nil }
            return SatelliteStatusReport(satelliteName: name, report: report, reportedAt: date)
        }.sorted { $0.reportedAt > $1.reportedAt }
    }
    nonisolated static func nameAliases(_ name: String) -> Set<String> {
        let base = name.components(separatedBy: "[")[0]
        let parts = base.components(separatedBy: CharacterSet(charactersIn: "()"))
        return Set(parts.map { part in
            let cleaned = part.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let regex = try! NSRegularExpression(pattern: #"\d+"#)
            var result = cleaned
            for match in regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)).reversed() {
                if let range = Range(match.range, in: result), let number = Int(result[range]) { result.replaceSubrange(range, with: String(number)) }
            }
            return result
        }.filter { $0.count >= 3 })
    }
    private enum CatalogError: LocalizedError {
        case http(String, Int), invalidResponse(String), noOrbits(String)
        var errorDescription: String? {
            switch self {
            case .http(let source, let code): "\(source) devolvió HTTP \(code)."
            case .invalidResponse(let source): "\(source) devolvió un formato inválido o incompleto."
            case .noOrbits(let reason): "No hay órbitas utilizables. \(reason)"
            }
        }
    }
}
