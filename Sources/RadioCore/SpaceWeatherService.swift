import Foundation

public enum SpaceWeatherSource: String, CaseIterable, Sendable {
    case kp, flux, scales, absorption, indices, bandInformation
    public var title: String {
        switch self {
        case .kp: "Kp NOAA"
        case .flux: "F10.7 NOAA"
        case .scales: "Escalas NOAA"
        case .absorption: "D-RAP NOAA"
        case .indices: "R12 ITU"
        case .bandInformation: "Band Info HamQSL"
        }
    }
    public var url: URL {
        let value = switch self {
        case .kp: "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json"
        case .flux: "https://services.swpc.noaa.gov/json/f107_cm_flux.json"
        case .scales: "https://services.swpc.noaa.gov/products/noaa-scales.json"
        case .absorption: "https://services.swpc.noaa.gov/text/drap_global_frequencies.txt"
        case .indices: "https://www.itu.int/en/ITU-R/study-groups/rsg3/Pages/rsg3-indices.aspx"
        case .bandInformation: "https://www.hamqsl.com/solarxml.php"
        }
        return URL(string: value)!
    }
}
public struct SpaceWeatherUpdate: Sendable {
    public let snapshot: SpaceWeatherSnapshot
    public let errors: [String: String]
    public let attemptedSources: Set<String>
}
public actor SpaceWeatherService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let cacheURL: URL
    private let transport: Transport
    private var lastBandInformationAttempt: Date?
    private struct Response: Sendable {
        let source: SpaceWeatherSource
        let data: Data?
        let error: String?
    }
    public init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RadioWorkbench/space-weather.json")
        self.transport = transport
    }
    public func cached() -> SpaceWeatherSnapshot? {
        guard let bytes = try? Data(contentsOf: cacheURL), bytes.count < 2_000_000 else { return nil }
        return try? JSONDecoder().decode(SpaceWeatherSnapshot.self, from: bytes)
    }
    public func download(previous: SpaceWeatherSnapshot? = nil, now: Date = Date(), forceIndices: Bool = false) async -> SpaceWeatherUpdate {
        var snapshot = previous ?? cached() ?? SpaceWeatherSnapshot(), errors: [String: String] = [:]
        let sources = SpaceWeatherSource.allCases.filter {
            if $0 == .bandInformation {
                let last = [lastBandInformationAttempt, snapshot.bandInformation?.fetchedAt, snapshot.bandInformationAttemptedAt].compactMap { $0 }.max()
                return last.map { now.timeIntervalSince($0) >= 3600 } ?? true
            }
            return $0 != .indices || forceIndices || (snapshot.indicesFetchedAt.map { now.timeIntervalSince($0) >= 24 * 3600 } ?? true)
        }
        if sources.contains(.bandInformation) { lastBandInformationAttempt = now; snapshot.bandInformationAttemptedAt = now }
        let transport = transport
        let responses = await withTaskGroup(of: Response.self, returning: [Response].self) { group in
            for source in sources {
                group.addTask {
                    do {
                        var request = URLRequest(url: source.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                        request.setValue("RadioWorkbench/0.7 propagation reader", forHTTPHeaderField: "User-Agent")
                        let (bytes, http) = try await transport(request)
                        guard http.statusCode == 200, bytes.count > 10, bytes.count <= 1_000_000,
                              http.url?.scheme == "https", http.url?.host == source.url.host else { throw URLError(.badServerResponse) }
                        return Response(source: source, data: bytes, error: nil)
                    } catch { return Response(source: source, data: nil, error: error.localizedDescription) }
                }
            }
            var results: [Response] = []
            for await result in group { results.append(result) }
            return results
        }
        for response in responses {
            guard let data = response.data else { errors[response.source.rawValue] = response.error; continue }
            do {
                switch response.source {
                case .kp: snapshot.kp = try SpaceWeatherParser.reading(data, field: "estimated_kp", fetchedAt: now)
                case .flux: snapshot.flux = try SpaceWeatherParser.reading(data, field: "flux", fetchedAt: now)
                case .scales: snapshot.scales = try SpaceWeatherParser.scales(data, fetchedAt: now)
                case .absorption:
                    guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                    snapshot.absorption = try SpaceWeatherParser.absorption(text, fetchedAt: now)
                case .indices:
                    guard let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                    snapshot.indices = try SpaceWeatherParser.indices(html); snapshot.indicesFetchedAt = now
                case .bandInformation:
                    snapshot.bandInformation = try BandInformationParser.parse(data, fetchedAt: now)
                }
            } catch { errors[response.source.rawValue] = error.localizedDescription }
        }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
        } catch { errors["cache"] = error.localizedDescription }
        return SpaceWeatherUpdate(snapshot: snapshot, errors: errors, attemptedSources: Set(sources.map(\.rawValue)))
    }
}
