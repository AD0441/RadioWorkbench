import Foundation

public struct IonosondeObservation: Codable, Hashable, Sendable, Identifiable {
    public let code: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let fof2MHz: Double?
    public let muf3000MHz: Double?
    public let hmf2Km: Double?
    public let confidence: Double?
    public let observedAt: Date
    public var id: String { code }

    public func distanceKm(from location: RadioLocation) -> Double {
        let rad = Double.pi / 180
        let lat1 = latitude * rad, lat2 = location.latitude * rad
        let deltaLat = (location.latitude - latitude) * rad
        let deltaLon = (location.longitude - longitude) * rad
        let a = pow(sin(deltaLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2)
        return 6_371 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public struct IonosondeSnapshot: Codable, Sendable {
    public let observations: [IonosondeObservation]
    public let fetchedAt: Date
    public init(observations: [IonosondeObservation], fetchedAt: Date) {
        self.observations = observations
        self.fetchedAt = fetchedAt
    }

    public func nearest(to location: RadioLocation, limit: Int = 5) -> [(IonosondeObservation, Double)] {
        observations.map { ($0, $0.distanceKm(from: location)) }
            .sorted { $0.1 < $1.1 }
            .prefix(max(0, limit))
            .map { ($0.0, $0.1) }
    }
}

public enum IonosondeParser {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> IonosondeSnapshot {
        guard data.count <= 3_000_000,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        var observations: [IonosondeObservation] = []
        for row in rows {
            guard let station = row["station"] as? [String: Any],
                  let code = (station["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty, code.count <= 12,
                  let name = (station["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let latitude = number(station["latitude"]), (-90...90).contains(latitude),
                  let longitude = number(station["longitude"]), (-180...360).contains(longitude),
                  let rawTime = row["time"] as? String, let observedAt = parseDate(rawTime),
                  observedAt <= fetchedAt.addingTimeInterval(300), observedAt >= fetchedAt.addingTimeInterval(-12 * 3600) else { continue }
            let fof2 = bounded(row["fof2"], range: 0...30)
            let muf = bounded(row["mufd"], range: 0...60)
            let hm = bounded(row["hmf2"], range: 100...1_000)
            let confidence = bounded(row["cs"], range: -1...100)
            guard fof2 != nil || muf != nil else { continue }
            observations.append(IonosondeObservation(code: code, name: name, latitude: latitude,
                longitude: longitude > 180 ? longitude - 360 : longitude, fof2MHz: fof2,
                muf3000MHz: muf, hmf2Km: hm, confidence: confidence, observedAt: observedAt))
        }
        guard !observations.isEmpty else { throw URLError(.cannotParseResponse) }
        let unique = Dictionary(observations.map { ($0.code, $0) }, uniquingKeysWith: { a, b in a.observedAt >= b.observedAt ? a : b })
        return IonosondeSnapshot(observations: unique.values.sorted { $0.name < $1.name }, fetchedAt: fetchedAt)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue.isFinite ? value.doubleValue : nil }
        if let value = value as? String { return Double(value).flatMap { $0.isFinite ? $0 : nil } }
        return nil
    }
    private static func bounded(_ value: Any?, range: ClosedRange<Double>) -> Double? {
        guard let value = number(value), range.contains(value) else { return nil }
        return value
    }
    private static func parseDate(_ value: String) -> Date? {
        if let date = SpaceWeatherParser.date(value) { return date }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

public actor IonosondeService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let minimumInterval: TimeInterval = 300
    public static let endpoint = URL(string: "https://prop.kc2g.com/api/stations.json?maxage=7200")!
    private let cacheURL: URL
    private let transport: Transport

    public init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true).appendingPathComponent("ionosonde-cache.json")
        self.transport = transport
    }

    public func cached() -> IonosondeSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 3_000_000 else { return nil }
        return try? JSONDecoder().decode(IonosondeSnapshot.self, from: data)
    }

    public func download(now: Date = Date()) async throws -> IonosondeSnapshot {
        if let old = cached(), now.timeIntervalSince(old.fetchedAt) < Self.minimumInterval { return old }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        request.setValue("RadioWorkbench/0.8 (regional ionosonde observations)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == "prop.kc2g.com",
              data.count > 20, data.count <= 3_000_000 else { throw URLError(.badServerResponse) }
        let snapshot = try IonosondeParser.parse(data, fetchedAt: now)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
        return snapshot
    }
}
