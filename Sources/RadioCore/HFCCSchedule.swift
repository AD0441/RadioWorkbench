import Foundation

/// A transmitter requirement in the HFCC/ITU standard schedule. Power is the
/// scheduled transmitter output in kW; it is not a measurement of radiated power.
public struct HFCCTransmission: Codable, Hashable, Sendable, Identifiable {
    public let frequencyKHz: Double
    public let startUTC: String
    public let stopUTC: String
    public let targetArea: String
    public let siteCode: String
    public let powerKW: Int?
    public let azimuthDegrees: Int?
    public let days: String
    public let startDate: String
    public let stopDate: String
    public let modulationCode: String
    public let language: String
    public let broadcasterCode: String
    public let managerCode: String
    public let raw: String

    public var id: String { raw }
    public var scheduledPowerWatts: Double? { powerKW.map { Double($0) * 1_000 } }
    /// HFCC numbers Sunday as 1; EiBi numbers Monday as 1. Do not pass these
    /// strings to BroadcastCalendar.dayMatch, which follows EiBi conventions.
    public func operates(on date: Date) -> Bool {
        let calendar = BroadcastCalendar.utc
        guard days.contains(String(calendar.component(.weekday, from: date))) else { return false }
        func boundary(_ text: String) -> Date? {
            guard text.count == 6, text.allSatisfy(\.isNumber) else { return nil }
            let parts = Array(text)
            guard let day = Int(String(parts[0..<2])), let month = Int(String(parts[2..<4])),
                  let year = Int(String(parts[4..<6])) else { return nil }
            let components = DateComponents(year: 2000 + year, month: month, day: day)
            guard let result = calendar.date(from: components), calendar.component(.day, from: result) == day,
                  calendar.component(.month, from: result) == month else { return nil }
            return result
        }
        guard let first = boundary(startDate), let last = boundary(stopDate) else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= first && day <= last
    }
    public var modulation: String {
        switch modulationCode.uppercased() {
        case "D": "AM · DSB (HFCC)"
        case "T": "SSB · HFCC (USB habitual)"
        case "N": "Digital · HFCC (posible DRM)"
        default: "Modulación no especificada"
        }
    }
}

public struct HFCCScheduleSnapshot: Codable, Sendable {
    public let transmissions: [HFCCTransmission]
    public let season: String
    public let sourceURL: URL
    public let fetchedAt: Date
    public init(transmissions: [HFCCTransmission], season: String, sourceURL: URL, fetchedAt: Date) {
        self.transmissions = transmissions
        self.season = season
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
    }

    /// A frequency/time/language candidate is not proof of transmitter identity.
    public func match(for entry: BroadcastEntry, candidates source: [HFCCTransmission]? = nil, on date: Date? = nil) -> HFCCTransmission? {
        guard let (entryStart, entryStop) = BroadcastCalendar.minutes(entry.time) else { return nil }
        func minutes(_ value: String, isStop: Bool = false) -> Int? {
            guard let raw = Int(value), value.count == 4, raw % 100 < 60 || (isStop && raw == 2400) else { return nil }
            return raw / 100 * 60 + raw % 100
        }
        let candidates = (source ?? transmissions).filter {
            if let date, !$0.operates(on: date) { return false }
            guard abs($0.frequencyKHz - entry.frequencyKHz) <= 1.0,
                  let start = minutes($0.startUTC), let stop = minutes($0.stopUTC, isStop: true) else { return false }
            return abs(start - entryStart) <= 5 && abs(stop - entryStop) <= 15
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        let language = entry.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard language.count >= 2 else { return nil }
        let languageMatches = candidates.filter { $0.language.lowercased().hasPrefix(language) }
        return languageMatches.count == 1 ? languageMatches[0] : nil
    }
}

public enum HFCCScheduleParser {
    /// Reads standard ITU fixed-width HFBC records. Column positions follow
    /// the ITU-BR file-format specification; malformed records are skipped.
    public static func parse(_ text: String, season: String, sourceURL: URL, fetchedAt: Date) throws -> HFCCScheduleSnapshot {
        var rows: [HFCCTransmission] = []
        for line in text.components(separatedBy: .newlines) {
            let bytes = Array(line.utf8)
            guard bytes.count >= 124, bytes[0] != 59 else { continue }
            func field(_ first: Int, _ last: Int) -> String {
                guard first > 0, last >= first, bytes.count >= last else { return "" }
                return String(decoding: bytes[(first - 1)..<last], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            }
            guard let frequency = Double(field(1, 5)), (1600...30000).contains(frequency),
                  let start = Int(field(7, 10)), (0...2359).contains(start), start % 100 < 60,
                  let stop = Int(field(12, 15)), (1...2400).contains(stop), stop == 2400 || stop % 100 < 60 else { continue }
            let target = field(17, 46)
            let site = field(48, 50)
            let rawPower = Int(field(52, 55))
            let azimuthField = field(57, 63)
            let azimuth = Int(azimuthField)
            let days = field(73, 79)
            let startDate = field(81, 86)
            let stopDate = field(88, 93)
            let modulation = field(95, 95).uppercased()
            let language = field(103, 112)
            let broadcaster = field(118, 120)
            let manager = field(122, 124)
            guard !site.isEmpty, !days.isEmpty, days.allSatisfy({ "1234567".contains($0) }),
                  ["D", "T", "N"].contains(modulation),
                  azimuth == nil || (0...359).contains(azimuth!) else { continue }
            rows.append(HFCCTransmission(
                frequencyKHz: frequency,
                startUTC: String(format: "%04d", start),
                stopUTC: String(format: "%04d", stop),
                targetArea: target,
                siteCode: site,
                powerKW: rawPower.flatMap { (1...5_000).contains($0) ? $0 : nil },
                azimuthDegrees: azimuth,
                days: days,
                startDate: startDate,
                stopDate: stopDate,
                modulationCode: modulation,
                language: language,
                broadcasterCode: broadcaster,
                managerCode: manager,
                raw: line
            ))
        }
        guard !rows.isEmpty else { throw URLError(.cannotParseResponse) }
        return HFCCScheduleSnapshot(transmissions: rows, season: season, sourceURL: sourceURL, fetchedAt: fetchedAt)
    }
}
