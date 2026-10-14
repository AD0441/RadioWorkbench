import Foundation

public struct PSKReceptionSpot: Codable, Hashable, Sendable, Identifiable {
    public let receiverCallsign: String
    public let receiverLocator: String
    public let senderCallsign: String
    public let senderLocator: String?
    public let frequencyHz: Int
    public let mode: String?
    public let reportedAt: Date
    public var id: String { "\(senderCallsign)|\(receiverLocator)|\(frequencyHz)|\(Int(reportedAt.timeIntervalSince1970))" }
    public var frequencyKHz: Double { Double(frequencyHz) / 1_000 }
}

public struct PSKReporterSnapshot: Codable, Sendable {
    public let grid: String
    public let spots: [PSKReceptionSpot]
    public let fetchedAt: Date
    public init(grid: String, spots: [PSKReceptionSpot], fetchedAt: Date) {
        self.grid = grid.uppercased()
        self.spots = spots
        self.fetchedAt = fetchedAt
    }
}

public enum Maidenhead {
    /// A four-character Maidenhead locator (roughly 100 × 100 km).
    public static func grid4(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let lon = min(longitude + 180, 360.0.nextDown), lat = min(latitude + 90, 180.0.nextDown)
        let fieldLon = Int(lon / 20), fieldLat = Int(lat / 10)
        let squareLon = Int((lon - Double(fieldLon * 20)) / 2)
        let squareLat = Int(lat - Double(fieldLat * 10))
        guard (0..<18).contains(fieldLon), (0..<18).contains(fieldLat), (0..<10).contains(squareLon), (0..<10).contains(squareLat) else { return nil }
        let a = UnicodeScalar(65 + fieldLon)!, b = UnicodeScalar(65 + fieldLat)!
        return "\(Character(a))\(Character(b))\(squareLon)\(squareLat)"
    }

    /// Center of a 4-, 6-, or 8-character Maidenhead locator.
    public static func center(_ locator: String) -> RadioLocation? {
        let value = locator.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(value)
        guard [4, 6, 8].contains(chars.count) else { return nil }
        var lon = -180.0, lat = -90.0
        var lonWidth = 20.0, latWidth = 10.0
        var finalLonWidth = lonWidth, finalLatWidth = latWidth
        for pair in 0..<(chars.count / 2) {
            let x = chars[pair * 2], y = chars[pair * 2 + 1]
            finalLonWidth = lonWidth; finalLatWidth = latWidth
            if pair == 0 {
                guard ("A"..."R").contains(String(x)), ("A"..."R").contains(String(y)) else { return nil }
                lon += Double(x.asciiValue! - 65) * lonWidth
                lat += Double(y.asciiValue! - 65) * latWidth
                lonWidth = 2; latWidth = 1
            } else if pair == 1 {
                guard x.isNumber, y.isNumber, let xi = x.wholeNumberValue, let yi = y.wholeNumberValue else { return nil }
                lon += Double(xi) * lonWidth
                lat += Double(yi) * latWidth
                lonWidth /= 24; latWidth /= 24
            } else if pair == 2 {
                guard ("A"..."X").contains(String(x)), ("A"..."X").contains(String(y)) else { return nil }
                lon += Double(x.asciiValue! - 65) * lonWidth
                lat += Double(y.asciiValue! - 65) * latWidth
                lonWidth /= 10; latWidth /= 10
            } else {
                guard x.isNumber, y.isNumber, let xi = x.wholeNumberValue, let yi = y.wholeNumberValue else { return nil }
                lon += Double(xi) * lonWidth
                lat += Double(yi) * latWidth
                lonWidth /= 24; latWidth /= 24
            }
        }
        return RadioLocation(latitude: lat + finalLatWidth / 2, longitude: lon + finalLonWidth / 2)
    }
}

public enum PSKReporterParser {
    public static func parse(_ data: Data, grid: String, fetchedAt: Date) throws -> PSKReporterSnapshot {
        guard data.count <= 2_000_000, isGrid4(grid) else { throw URLError(.dataLengthExceedsMaximum) }
        let collector = SpotCollector(fetchedAt: fetchedAt)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), collector.rootSeen else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        guard collector.spots.count <= 5_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let unique = Dictionary(collector.spots.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.reportedAt >= b.reportedAt ? a : b })
        return PSKReporterSnapshot(grid: grid, spots: unique.values.sorted { $0.reportedAt > $1.reportedAt }, fetchedAt: fetchedAt)
    }

    public static func isGrid4(_ value: String) -> Bool {
        let s = value.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 4 else { return false }
        let chars = Array(s)
        return chars[0] >= "A" && chars[0] <= "R" && chars[1] >= "A" && chars[1] <= "R"
            && chars[2].isNumber && chars[3].isNumber
    }

    private final class SpotCollector: NSObject, XMLParserDelegate {
        let fetchedAt: Date
        var spots: [PSKReceptionSpot] = []
        var rootSeen = false
        init(fetchedAt: Date) { self.fetchedAt = fetchedAt }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
            if elementName == "receptionReports" { rootSeen = true; return }
            guard elementName == "receptionReport",
                  let sender = attributes["senderCallsign"], validCallsign(sender),
                  let rawFrequency = attributes["frequency"], let frequency = Int(rawFrequency), (100_000...1_300_000_000).contains(frequency),
                  let rawTime = attributes["flowStartSeconds"], let epoch = TimeInterval(rawTime), epoch.isFinite else { return }
            let date = Date(timeIntervalSince1970: epoch)
            guard date <= fetchedAt.addingTimeInterval(300), date >= fetchedAt.addingTimeInterval(-24 * 3600) else { return }
            let receiver = attributes["receiverCallsign"] ?? ""
            let locatorValue = attributes["receiverLocator"] ?? ""
            let locator = Maidenhead.center(locatorValue) == nil ? "" : locatorValue.uppercased()
            let senderLocatorValue = attributes["senderLocator"] ?? ""
            let senderLocator = Maidenhead.center(senderLocatorValue) == nil ? nil : senderLocatorValue.uppercased()
            let mode = attributes["mode"]
            spots.append(PSKReceptionSpot(receiverCallsign: receiver, receiverLocator: locator, senderCallsign: sender.uppercased(), senderLocator: senderLocator, frequencyHz: frequency, mode: mode, reportedAt: date))
        }

        private func validCallsign(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 16 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "/" }
        }
    }
}

public enum PSKReporterError: LocalizedError {
    case queryCooldown
    public var errorDescription: String? {
        switch self {
        case .queryCooldown: "PSK Reporter permite consultar como máximo una vez cada cinco minutos."
        }
    }
}

public actor PSKReporterService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let minimumInterval: TimeInterval = 300
    public static let endpoint = URL(string: "https://retrieve.pskreporter.info/query")!
    private let cacheURL: URL
    private let attemptURL: URL
    private let transport: Transport

    public init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) {
        let resolvedCacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true).appendingPathComponent("psk-reporter-cache.json")
        self.cacheURL = resolvedCacheURL
        self.attemptURL = resolvedCacheURL.appendingPathExtension("last-query")
        self.transport = transport
    }

    public func cached() -> PSKReporterSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 2_000_000 else { return nil }
        return try? JSONDecoder().decode(PSKReporterSnapshot.self, from: data)
    }

    public func download(grid: String, now: Date = Date()) async throws -> PSKReporterSnapshot {
        let normalized = grid.uppercased()
        guard PSKReporterParser.isGrid4(normalized) else { throw URLError(.badURL) }
        if let old = cached(), old.grid == normalized, now.timeIntervalSince(old.fetchedAt) < Self.minimumInterval {
            return old
        }
        if let lastAttempt = lastAttempt(), now.timeIntervalSince(lastAttempt) < Self.minimumInterval {
            throw PSKReporterError.queryCooldown
        }
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "receiverCallsign", value: normalized),
            URLQueryItem(name: "modify", value: "grid"),
            URLQueryItem(name: "flowStartSeconds", value: "-3600"),
            URLQueryItem(name: "rptlimit", value: "100"),
            URLQueryItem(name: "noactive", value: "1")
        ]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("RadioWorkbench/0.8 (PSK Reporter optional reception view)", forHTTPHeaderField: "User-Agent")
        try? FileManager.default.createDirectory(at: attemptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(String(now.timeIntervalSince1970).utf8).write(to: attemptURL, options: .atomic)
        let (data, response) = try await transport(request)
        guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == Self.endpoint.host,
              data.count > 20, data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        let snapshot = try PSKReporterParser.parse(data, grid: normalized, fetchedAt: now)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: cacheURL, options: .atomic)
        return snapshot
    }

    private func lastAttempt() -> Date? {
        guard let data = try? Data(contentsOf: attemptURL), let timestamp = Double(String(decoding: data, as: UTF8.self)), timestamp.isFinite else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}
