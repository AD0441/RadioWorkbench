import Foundation

public struct NoaaThreeDayForecast: Codable, Sendable {
    public let issuedAt: Date
    public let fetchedAt: Date
    public let datesUTC: [Date]
    /// Eight 3-hour forecast periods by three UTC dates.
    public let kpByThreeHour: [[Double]]
    public let s1OrGreaterProbability: [Int]
    public let r1ToR2Probability: [Int]
    public let r3OrGreaterProbability: [Int]
    public let geomagneticRationale: String
    public let solarRationale: String
    public let blackoutRationale: String

    public var dailyMaximumKp: [Double] {
        guard kpByThreeHour.count == 8, kpByThreeHour.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && (0...9).contains($0) } }) else { return [] }
        return (0..<3).map { day in kpByThreeHour.reduce(0) { max($0, $1[day]) } }
    }
}

public enum NoaaThreeDayForecastParser {
    private static let monthByName = Dictionary(uniqueKeysWithValues: zip(
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1...12))

    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> NoaaThreeDayForecast {
        guard data.count <= 100_000, let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        let lines = text.components(separatedBy: .newlines)
        guard let issueLine = lines.first(where: { $0.hasPrefix(":Issued:") }),
              let issued = parseIssued(String(issueLine.dropFirst(8))) else { throw URLError(.cannotParseResponse) }
        guard let kpHeading = lines.firstIndex(where: { $0.contains("NOAA Kp index breakdown") }),
              let dateLine = lines.dropFirst(kpHeading + 1).prefix(5).first(where: { dateLabels($0).count == 3 }) else { throw URLError(.cannotParseResponse) }
        let dates = makeDates(dateLabels(dateLine), issuedAt: issued)
        guard dates.count == 3 else { throw URLError(.cannotParseResponse) }
        let kpRows = lines.dropFirst(kpHeading + 1).prefix(14).compactMap { line -> [Double]? in
            let pieces = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let period = pieces.first, period.hasSuffix("UT") else { return nil }
            let values = pieces.dropFirst().compactMap(Double.init)
            return values.count == 3 ? values : nil
        }
        guard kpRows.count == 8, kpRows.joined().allSatisfy({ $0.isFinite && (0...9.0).contains($0) }) else { throw URLError(.cannotParseResponse) }
        guard let s1 = probabilityRow(containing: "S1 or greater", in: lines),
              let r12 = probabilityRow(containing: "R1-R2", in: lines),
              let r3 = probabilityRow(containing: "R3 or greater", in: lines) else { throw URLError(.cannotParseResponse) }
        return NoaaThreeDayForecast(issuedAt: issued, fetchedAt: fetchedAt, datesUTC: dates, kpByThreeHour: kpRows,
                                    s1OrGreaterProbability: s1, r1ToR2Probability: r12, r3OrGreaterProbability: r3,
                                    geomagneticRationale: rationale(after: "A. NOAA Geomagnetic", in: lines),
                                    solarRationale: rationale(after: "B. NOAA Solar Radiation", in: lines),
                                    blackoutRationale: rationale(after: "C. NOAA Radio Blackout", in: lines))
    }

    private static func parseIssued(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy MMM dd HHmm 'UTC'"
        return formatter.date(from: value.trimmingCharacters(in: .whitespaces))
    }

    private static func dateLabels(_ line: String) -> [(Int, Int)] {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        var values: [(Int, Int)] = []
        for index in 0..<max(0, tokens.count - 1) {
            if let month = monthByName[String(tokens[index].prefix(3))], let day = Int(tokens[index + 1]), (1...31).contains(day) {
                values.append((month, day))
            }
        }
        return values
    }

    private static func makeDates(_ labels: [(Int, Int)], issuedAt: Date) -> [Date] {
        let calendar = BroadcastCalendar.utc
        let issuedYear = calendar.component(.year, from: issuedAt)
        var lastDate = issuedAt
        return labels.compactMap { month, day in
            var year = issuedYear
            var components = DateComponents(year: year, month: month, day: day)
            guard var candidate = calendar.date(from: components) else { return nil }
            if candidate < issuedAt.addingTimeInterval(-180 * 86_400) { year += 1; components.year = year; candidate = calendar.date(from: components) ?? candidate }
            if candidate < lastDate.addingTimeInterval(-86_400) { year += 1; components.year = year; candidate = calendar.date(from: components) ?? candidate }
            lastDate = candidate
            return candidate
        }
    }

    private static func probabilityRow(containing label: String, in lines: [String]) -> [Int]? {
        guard let line = lines.first(where: { $0.localizedCaseInsensitiveContains(label) }) else { return nil }
        let values = line.split(whereSeparator: \.isWhitespace).compactMap { token -> Int? in
            guard token.hasSuffix("%") else { return nil }
            return Int(token.dropLast())
        }
        guard values.count >= 3, values.suffix(3).allSatisfy({ (0...100).contains($0) }) else { return nil }
        return Array(values.suffix(3))
    }

    private static func rationale(after heading: String, in lines: [String]) -> String {
        guard let section = lines.firstIndex(where: { $0.hasPrefix(heading) }),
              let start = lines[section...].firstIndex(where: { $0.hasPrefix("Rationale:") }) else { return "" }
        var parts = [String(lines[start].dropFirst("Rationale:".count)).trimmingCharacters(in: .whitespaces)]
        for line in lines.dropFirst(start + 1) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") || line.range(of: "^[A-C]\\.", options: .regularExpression) != nil { break }
            parts.append(line.trimmingCharacters(in: .whitespaces))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public enum NoaaThreeDayForecastError: LocalizedError {
    case retryCooldown
    public var errorDescription: String? { "NOAA SWPC se consultó hace poco; el siguiente reintento es en menos de 30 minutos." }
}

public actor NoaaThreeDayForecastService {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let endpoint = URL(string: "https://services.swpc.noaa.gov/text/3-day-forecast.txt")!
    public static let minimumInterval: TimeInterval = 6 * 3600
    private let cacheURL: URL
    private let transport: Transport
    private var lastAttempt: Date?

    public init(cacheURL: URL? = nil, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true).appendingPathComponent("noaa-3day-forecast.json")
        self.transport = transport
    }

    public func cached() -> NoaaThreeDayForecast? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 100_000 else { return nil }
        return try? JSONDecoder().decode(NoaaThreeDayForecast.self, from: data)
    }

    public func download(now: Date = Date()) async throws -> NoaaThreeDayForecast {
        if let old = cached(), now.timeIntervalSince(old.fetchedAt) < Self.minimumInterval { return old }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < 30 * 60 { throw NoaaThreeDayForecastError.retryCooldown }
        lastAttempt = now
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("RadioWorkbench/0.8 (NOAA SWPC forecast)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == Self.endpoint.host else { throw URLError(.badServerResponse) }
        let forecast = try NoaaThreeDayForecastParser.parse(data, fetchedAt: now)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(forecast).write(to: cacheURL, options: .atomic)
        return forecast
    }
}
