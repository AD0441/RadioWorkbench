import Foundation

public struct SatellitePosition: Hashable, Sendable {
    public let latitude: Double, longitude: Double, altitudeKm: Double
}
public struct SatelliteObservation: Hashable, Sendable {
    public let azimuthDegrees: Double, elevationDegrees: Double, rangeKm: Double
    public var rangeRateKmPerSecond: Double = 0
    /// Positive shift means the received downlink is above its nominal frequency.
    public func dopplerHz(frequencyMHz: Double) -> Double? {
        guard frequencyMHz.isFinite, (0.01...100000).contains(frequencyMHz) else { return nil }
        return -frequencyMHz * 1_000_000 * rangeRateKmPerSecond / 299792.458
    }
}
public struct SatelliteTrackSample: Sendable, Identifiable {
    public let date: Date
    public let position: SatellitePosition
    public let observation: SatelliteObservation
    public var id: Date { date }
}

public enum SatelliteElementParser {
    /// CelesTrak GP omits TIME_SYSTEM=UTC and may omit Z. Do not interpret such epochs in local time.
    public static func utcDate(_ text: String) -> Date? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?$"#, options: .regularExpression) != nil { value += "Z" }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    public static func catalogNumber(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if let number = Int(value), number > 0 { return number }
        let bytes = Array(value.uppercased().utf8), letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ".utf8)
        guard bytes.count == 5, let index = letters.firstIndex(of: bytes[0]), let suffix = Int(String(decoding: bytes.dropFirst(), as: UTF8.self)) else { return nil }
        return (index + 10) * 10_000 + suffix
    }
    public static func omm(_ data: Data) throws -> [TLEOrbit] {
        guard data.count <= 8_000_000, let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw SatelliteElementError.invalidData }
        let orbits = rows.compactMap { row -> TLEOrbit? in
            func number(_ key: String) -> Double? { (row[key] as? NSNumber)?.doubleValue ?? (row[key] as? String).flatMap(Double.init) }
            guard let name = row["OBJECT_NAME"] as? String, !name.isEmpty, name.count <= 200,
                let id = number("NORAD_CAT_ID"), id > 0, id <= 999_999_999, id.rounded() == id,
                let epoch = (row["EPOCH"] as? String).flatMap(utcDate), let n = number("MEAN_MOTION"),
                let e = number("ECCENTRICITY"), let i = number("INCLINATION"), let r = number("RA_OF_ASC_NODE"),
                let p = number("ARG_OF_PERICENTER"), let m = number("MEAN_ANOMALY") else { return nil }
            let orbit = TLEOrbit(name: name, catalogNumber: Int(id), epoch: epoch, meanMotionRevolutionsPerDay: n,
                eccentricity: e, inclinationDegrees: i, raanDegrees: r, argumentOfPerigeeDegrees: p, meanAnomalyDegrees: m, bstar: number("BSTAR"))
            return orbit.isValid ? orbit : nil
        }
        guard !orbits.isEmpty else { throw SatelliteElementError.invalidData }
        return orbits
    }
    private static func drag(_ text: String) -> Double? {
        let b = Array(text.utf8)
        guard b.count == 8, [32,43,45].contains(b[0]), b[1..<6].allSatisfy({ (48...57).contains($0) }),
              [43,45].contains(b[6]), (48...57).contains(b[7]) else { return nil }
        return Double((b[0] == 45 ? "-" : "") + "0." + String(decoding: b[1..<6], as: UTF8.self) + "e" + String(decoding: b[6..<8], as: UTF8.self))
    }
    public static func tle(_ data: Data) throws -> [TLEOrbit] {
        guard data.count <= 8_000_000, let text = String(data: data, encoding: .utf8) else { throw SatelliteElementError.invalidData }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
        var result: [TLEOrbit] = [], name = ""
        func valid(_ bytes: [UInt8], digit: UInt8) -> Bool {
            guard bytes.count >= 69, bytes[0] == digit, bytes[1] == 32, (48...57).contains(bytes[68]) else { return false }
            let sum = bytes.prefix(68).reduce(0) { $0 + ((48...57).contains($1) ? Int($1 - 48) : $1 == 45 ? 1 : 0) }
            return sum % 10 == Int(bytes[68] - 48)
        }
        var index = 0
        while index < lines.count {
            let first = Array(lines[index].utf8)
            if !lines[index].hasPrefix("1 ") && !lines[index].hasPrefix("2 ") { name = lines[index].replacingOccurrences(of: "^0 ", with: "", options: .regularExpression); index += 1; continue }
            guard index + 1 < lines.count else { break }
            let second = Array(lines[index + 1].utf8)
            guard valid(first, digit: 49), valid(second, digit: 50) else { index += 1; continue }
            func field(_ b: [UInt8], _ range: Range<Int>) -> String { String(decoding: b[range], as: UTF8.self).trimmingCharacters(in: .whitespaces) }
            guard let id = catalogNumber(field(first, 2..<7)), id == catalogNumber(field(second, 2..<7)),
                let shortYear = Int(field(first, 18..<20)), let day = Double(field(first, 20..<32)),
                let n = Double(field(second, 52..<63)), let e = Double("0." + field(second, 26..<33)),
                let i = Double(field(second, 8..<16)), let r = Double(field(second, 17..<25)),
                let p = Double(field(second, 34..<42)), let m = Double(field(second, 43..<51)) else { index += 2; continue }
            let year = shortYear >= 57 ? 1900 + shortYear : 2000 + shortYear
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                let next = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)), day >= 1,
                day < next.timeIntervalSince(start) / 86_400 + 1 else { index += 2; continue }
            let orbit = TLEOrbit(name: name.isEmpty ? "NORAD \(id)" : String(name.prefix(200)), catalogNumber: id,
                epoch: start.addingTimeInterval((day - 1) * 86_400), meanMotionRevolutionsPerDay: n,
                eccentricity: e, inclinationDegrees: i, raanDegrees: r, argumentOfPerigeeDegrees: p, meanAnomalyDegrees: m, bstar: Self.drag(String(decoding: first[53..<61], as: UTF8.self)))
            if orbit.isValid { result.append(orbit) }
            index += 2
        }
        guard !result.isEmpty else { throw SatelliteElementError.invalidData }
        return result
    }
}
public enum SatelliteElementError: LocalizedError {
    case invalidData
    public var errorDescription: String? { "La fuente no devolvió elementos orbitales válidos." }
}
public extension SatellitePassPredictor {
    static func track(orbit: TLEOrbit, pass: SatellitePass, observer: RadioLocation, stepSeconds: Double = 10) -> [SatelliteTrackSample] {
        guard stepSeconds.isFinite, stepSeconds >= 2, pass.los > pass.aos, pass.los.timeIntervalSince(pass.aos) <= 86_400 else { return [] }
        var samples: [SatelliteTrackSample] = [], date = pass.aos
        while date <= pass.los {
            if let position = orbit.position(at: date), let observation = orbit.observation(at: date, latitude: observer.latitude, longitude: observer.longitude) {
                samples.append(SatelliteTrackSample(date: date, position: position, observation: observation))
            }
            if date == pass.los { break }
            date = min(date.addingTimeInterval(stepSeconds), pass.los)
        }
        return samples
    }
    /// Break at ±180° rather than drawing a spurious straight line across the world.
    static func segments(_ samples: [SatelliteTrackSample]) -> [[SatelliteTrackSample]] {
        var result: [[SatelliteTrackSample]] = [], current: [SatelliteTrackSample] = []
        for sample in samples {
            if let last = current.last, abs(last.position.longitude - sample.position.longitude) > 180 { result.append(current); current = [] }
            current.append(sample)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
