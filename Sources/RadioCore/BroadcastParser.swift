import Foundation

public enum BroadcastParser {
    public static func text(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
    public static func csv(_ text: String) -> (entries: [BroadcastEntry], skipped: Int) {
        var entries: [BroadcastEntry] = [], skipped = 0
        var seen = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty || raw.hasPrefix("#") || raw.hasPrefix("kHz:") { continue }
            let p = raw.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 11, let freq = Double(p[0]), freq.isFinite, (10...300000).contains(freq),
                  BroadcastCalendar.minutes(p[1]) != nil, !p[4].isEmpty, let persistence = Int(p[8]) else { skipped += 1; continue }
            guard seen.insert(raw).inserted else { continue }
            entries.append(BroadcastEntry(frequencyKHz: freq, time: p[1], days: p[2], country: p[3], station: p[4], language: p[5], target: p[6], site: p[7], persistence: persistence, startDate: p[9], stopDate: p[10], raw: raw))
        }
        return (entries, skipped)
    }
}
