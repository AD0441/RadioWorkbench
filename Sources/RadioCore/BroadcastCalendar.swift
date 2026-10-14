import Foundation

public enum BroadcastActivity: String, Sendable {
    case scheduled = "Prevista ahora", uncertain = "Horario incierto", off = "Fuera de horario", inactive = "Inactiva"
}

public enum BroadcastCalendar {
    public static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private static let dayNames = ["Mo","Tu","We","Th","Fr","Sa","Su"]
    public static func minutes(_ time: String) -> (Int, Int)? {
        let p = time.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 2 else { return nil }
        func minute(_ s: Substring, end: Bool) -> Int? {
            guard s.count == 4, s.allSatisfy({ $0.isNumber }), let h = Int(s.prefix(2)), let m = Int(s.suffix(2)), m < 60, h < 24 || (end && h == 24 && m == 0) else { return nil }
            return h * 60 + m
        }
        guard let a = minute(p[0], end: false), let b = minute(p[1], end: true), a != b else { return nil }
        return (a,b)
    }
    public static func season(at date: Date) -> String {
        let y = utc.component(.year, from: date)
        func lastSunday(_ month: Int) -> Date {
            let next = utc.date(from: DateComponents(year: y, month: month + 1, day: 1))!
            let last = utc.date(byAdding: .day, value: -1, to: next)!
            return utc.date(byAdding: .day, value: -(utc.component(.weekday, from: last) - 1), to: last)!
        }
        let march = lastSunday(3), october = lastSunday(10)
        let summer = date >= march && date < october
        let year = date < march ? y - 1 : y
        return String(format: "%@%02d", summer ? "a" : "b", year % 100)
    }
    public static func activity(_ entry: BroadcastEntry, at now: Date, season: String) -> BroadcastActivity {
        if entry.persistence % 90 == 8 { return .inactive }
        guard let (start, end) = minutes(entry.time) else { return .off }
        let minute = utc.component(.hour, from: now) * 60 + utc.component(.minute, from: now)
        let overnight = start > end
        guard overnight ? (minute >= start || minute < end) : (minute >= start && minute < end) else { return .off }
        let anchor = overnight && minute < end ? utc.date(byAdding: .day, value: -1, to: now)! : now
        if entry.persistence % 90 == 6, !withinSeasonDates(entry, anchor: anchor, season: season) { return .off }
        switch dayMatch(entry.days, at: anchor) {
        case true?: return .scheduled
        case false?: return .off
        case nil: return .uncertain
        }
    }
    /// Finds the next confidently scheduled UTC start; irregular or unknown day rules are skipped.
    public static func nextScheduledStart(_ entry: BroadcastEntry, after date: Date, daysAhead: Int = 14) -> Date? {
        guard daysAhead > 0, let (start, _) = minutes(entry.time), entry.persistence % 90 != 8 else { return nil }
        let midnight = utc.startOfDay(for: date)
        for offset in 0...daysAhead {
            guard let day = utc.date(byAdding: .day, value: offset, to: midnight) else { continue }
            var components = utc.dateComponents([.year, .month, .day], from: day)
            components.hour = start / 60; components.minute = start % 60; components.second = 0
            guard let candidate = utc.date(from: components), candidate > date,
                  activity(entry, at: candidate, season: season(at: candidate)) == .scheduled else { continue }
            return candidate
        }
        return nil
    }
    // nil retains uncertainty for irregular, alternating, religious and unsupported calendars.
    public static func dayMatch(_ token: String, at date: Date) -> Bool? {
        let d = token.trimmingCharacters(in: .whitespaces)
        if d.isEmpty || d == "USB" || d == "LSB" { return true }
        let weekday = (utc.component(.weekday, from: date) + 5) % 7
        if d.allSatisfy({ "1234567".contains($0) }) { return d.contains(String(weekday + 1)) }
        if let i = dayNames.firstIndex(of: d) { return i == weekday }
        if d.contains(",") {
            let results = d.split(separator: ",").map { dayMatch(String($0), at: date) }
            if results.contains(true) { return true }
            return results.contains(where: { $0 == nil }) ? nil : false
        }
        let range = d.split(separator: "-")
        if range.count == 2, let a = dayNames.firstIndex(of: String(range[0])), let b = dayNames.firstIndex(of: String(range[1])) { return a <= b ? (a...b).contains(weekday) : weekday >= a || weekday <= b }
        if d == "MF-15" { return weekday < 5 && utc.component(.day, from: date) <= 15 }
        if d.hasPrefix("1."), let i = dayNames.firstIndex(of: String(d.dropFirst(2))) { return weekday == i && utc.component(.day, from: date) <= 7 }
        if d == "Last7" { return weekday == 6 && utc.component(.month, from: utc.date(byAdding: .day, value: 7, to: date)!) != utc.component(.month, from: date) }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        if d.count >= 4, let month = months.firstIndex(of: String(d.suffix(3))), let day = Int(d.dropLast(3)) { return utc.component(.month, from: date) == month + 1 && utc.component(.day, from: date) == day }
        return nil
    }
    private static func withinSeasonDates(_ e: BroadcastEntry, anchor: Date, season: String) -> Bool {
        let md = utc.component(.month, from: anchor) * 100 + utc.component(.day, from: anchor)
        func mdValue(_ s: String) -> Int? {
            let date = String(s.split(separator: "[", maxSplits: 1).first ?? "")
            guard date.count == 4, let d = Int(date.prefix(2)), let m = Int(date.suffix(2)), (1...31).contains(d), (1...12).contains(m) else { return nil }
            return m * 100 + d
        }
        let start = mdValue(e.startDate), end = mdValue(e.stopDate)
        if let start, let end { return start <= end ? (start...end).contains(md) : md >= start || md <= end }
        if let start { return season.hasPrefix("b") && start >= 1000 && md < 400 ? true : md >= start }
        if let end { return season.hasPrefix("b") && end < 400 && md >= 1000 ? true : md <= end }
        return true
    }
}
