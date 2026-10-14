import Foundation

public struct SpaceReading: Codable, Sendable {
    public let value: Double
    public let observedAt: Date
    public let fetchedAt: Date
    public func isFresh(at date: Date, maxAge: Double) -> Bool {
        let age = date.timeIntervalSince(observedAt)
        return value.isFinite && age >= -300 && age <= maxAge
    }
}
public struct SpaceScales: Codable, Sendable {
    public let radio: Int?
    public let radiation: Int?
    public let geomagnetic: Int?
    public let observedAt: Date
    public let fetchedAt: Date
}
public struct IonosphericIndex: Codable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let r12: Double
    public let predicted: Bool
    public var id: String { String(format: "%04d-%02d", year, month) }
}
public struct AbsorptionCell: Sendable {
    public let latitude: Double
    public let longitude: Double
    public let highestAffectedMHz: Double
}
public struct AbsorptionGrid: Codable, Sendable {
    public let longitudes: [Double]
    public let latitudes: [Double]
    public let frequencies: [[Double]]
    public let validAt: Date
    public let fetchedAt: Date
    public func nearest(to location: RadioLocation) -> AbsorptionCell? {
        guard frequencies.count == latitudes.count,
              let row = latitudes.indices.min(by: { abs(latitudes[$0]-location.latitude) < abs(latitudes[$1]-location.latitude) }),
              let col = longitudes.indices.min(by: { Self.longitudeDistance(longitudes[$0], location.longitude) < Self.longitudeDistance(longitudes[$1], location.longitude) }),
              frequencies[row].count == longitudes.count else { return nil }
        let value = frequencies[row][col]
        guard value.isFinite, value >= 0 else { return nil }
        return AbsorptionCell(latitude: latitudes[row], longitude: longitudes[col], highestAffectedMHz: value)
    }
    private static func longitudeDistance(_ a: Double, _ b: Double) -> Double { min(abs(a-b), 360-abs(a-b)) }
    public func isFresh(at date: Date) -> Bool { (-300...900).contains(date.timeIntervalSince(validAt)) }
}
public struct SpaceWeatherSnapshot: Codable, Sendable {
    public var kp: SpaceReading?
    public var flux: SpaceReading?
    public var scales: SpaceScales?
    public var absorption: AbsorptionGrid?
    public var indices: [IonosphericIndex] = []
    public var indicesFetchedAt: Date?
    public var bandInformation: BandInformationSnapshot?
    public var bandInformationAttemptedAt: Date?
    public init() {}
    public func index(at date: Date) -> IonosphericIndex? {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        return indices.first { $0.year == c.component(.year, from: date) && $0.month == c.component(.month, from: date) }
    }
}

public enum SpaceWeatherParser {
    public static func date(_ text: String) -> Date? {
        let s = text.hasSuffix("Z") || text.contains("+") ? text : text + "Z"
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions.insert(.withFractionalSeconds)
        return f.date(from: s)
    }
    public static func reading(_ data: Data, field: String, fetchedAt: Date) throws -> SpaceReading {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        let valid = rows.compactMap { row -> SpaceReading? in
            guard let value = row[field] as? Double, value.isFinite, value >= 0,
                  let time = row["time_tag"] as? String, let date = date(time), date <= fetchedAt.addingTimeInterval(300) else { return nil }
            if field == "estimated_kp", value > 9 { return nil }
            if field == "flux", (row["frequency"] as? Int) != 2800 { return nil }
            return SpaceReading(value: value, observedAt: date, fetchedAt: fetchedAt)
        }
        guard let latest = valid.max(by: { $0.observedAt < $1.observedAt }) else { throw URLError(.cannotParseResponse) }
        return latest
    }
    public static func scales(_ data: Data, fetchedAt: Date) throws -> SpaceScales {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let row = root["0"] as? [String: Any],
              let d = row["DateStamp"] as? String, let t = row["TimeStamp"] as? String, let time = date(d + "T" + t),
              time <= fetchedAt.addingTimeInterval(300) else { throw URLError(.cannotParseResponse) }
        func scale(_ key: String) -> Int? {
            guard let s = (row[key] as? [String: Any])?["Scale"] as? String, let i = Int(s), (0...5).contains(i) else { return nil }
            return i
        }
        let r = scale("R"), s = scale("S"), g = scale("G")
        guard r != nil || s != nil || g != nil else { throw URLError(.cannotParseResponse) }
        return SpaceScales(radio: r, radiation: s, geomagnetic: g, observedAt: time, fetchedAt: fetchedAt)
    }
    public static func absorption(_ text: String, fetchedAt: Date) throws -> AbsorptionGrid {
        var validAt: Date?, longitudes: [Double] = [], latitudes: [Double] = [], rows: [[Double]] = []
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("# Product Valid At : ") {
                let value = String(line.dropFirst(21)).trimmingCharacters(in: .whitespaces)
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
                validAt = f.date(from: value)
            }
            if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.contains("|") {
                let parts = line.components(separatedBy: "|")
                guard parts.count == 2, let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)), abs(lat) <= 90 else { throw URLError(.cannotParseResponse) }
                let tokens = parts[1].split(whereSeparator: \.isWhitespace)
                let values = tokens.compactMap { Double($0) }
                guard values.count == longitudes.count, values.count == tokens.count, values.allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { throw URLError(.cannotParseResponse) }
                latitudes.append(lat); rows.append(values)
            } else if longitudes.isEmpty {
                let tokens = line.split(whereSeparator: \.isWhitespace)
                let values = tokens.compactMap { Double($0) }
                if values.count >= 2, values.count == tokens.count, values.allSatisfy({ $0.isFinite && abs($0) <= 180 }) { longitudes = values }
            }
        }
        guard let validAt, validAt <= fetchedAt.addingTimeInterval(300), latitudes.count >= 2,
              Set(latitudes).count == latitudes.count, Set(longitudes).count == longitudes.count else { throw URLError(.cannotParseResponse) }
        return AbsorptionGrid(longitudes: longitudes, latitudes: latitudes, frequencies: rows, validAt: validAt, fetchedAt: fetchedAt)
    }
    public static func indices(_ html: String) throws -> [IonosphericIndex] {
        func matches(_ pattern: String, _ value: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
            return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { Range($0.range(at: 1), in: value).map { String(value[$0]) } }
        }
        // Select the R12 table, then retain its year row groups; other page tables are unrelated.
        guard let table = matches("<table[^>]*>(.*?)</table>", html).first(where: { $0.contains("R12") }) else { throw URLError(.cannotParseResponse) }
        var year: Int?, result: [IonosphericIndex] = []
        for row in matches("<tr[^>]*>(.*?)</tr>", table) {
            let cells = matches("<t[dh][^>]*>(.*?)</t[dh]>", row).map { $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            var offset = 0
            if let first = cells.first.flatMap(Int.init), (1900...2100).contains(first), cells.count == 6 { year = first; offset = 1 }
            guard let year, cells.count == 5 + offset, let month = Int(cells[offset]), (1...12).contains(month) else { continue }
            let raw = cells[offset+2]
            guard let r = Double(raw.components(separatedBy: " ").first ?? ""), r.isFinite, (1...311).contains(r) else { continue }
            result.append(IonosphericIndex(year: year, month: month, r12: r, predicted: raw.localizedCaseInsensitiveContains("predicted")))
        }
        guard result.count >= 12, Set(result.map(\.id)).count == result.count else { throw URLError(.cannotParseResponse) }
        return result
    }
}
