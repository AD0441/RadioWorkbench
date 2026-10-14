import Foundation

public struct BroadcastSite: Codable, Hashable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public func distanceAndBearing(latitude: Double, longitude: Double) -> (Double, Double) {
        let rad = Double.pi / 180
        let a = latitude * rad, b = self.latitude * rad, delta = (self.longitude - longitude) * rad
        let h = pow(sin((b-a)/2), 2) + cos(a)*cos(b)*pow(sin(delta/2), 2)
        let km = 6371 * 2 * asin(sqrt(min(1,max(0,h))))
        let bearing = (atan2(sin(delta)*cos(b), cos(a)*sin(b)-sin(a)*cos(b)*cos(delta))/rad + 360).truncatingRemainder(dividingBy: 360)
        return (km,bearing)
    }
}

public struct BroadcastReference: Codable, Sendable {
    public var countries: [String: String] = [:]
    public var languages: [String: String] = [:]
    public var targets: [String: String] = [:]
    public var sites: [String: BroadcastSite] = [:]
    public init() {}
    public func targetName(_ code: String) -> String {
        if let name = targets[code] ?? countries[code] { return name }
        let prefixes = ["N":"North", "S":"South", "E":"East", "W":"West", "C":"Central"]
        let bases = ["Af":"Africa", "Am":"America", "As":"Asia", "Eu":"Europe"]
        if code.count == 3, let first = code.first, let prefix = prefixes[String(first)], let base = bases[String(code.dropFirst())] { return "\(prefix) \(base)" }
        return code
    }
    public func site(for entry: BroadcastEntry) -> BroadcastSite? {
        let raw = entry.site
        // Keep ambiguous multi-site listings unresolved instead of guessing a location.
        if raw.contains(",") || raw.contains(" ") { return nil }
        if raw.hasPrefix("/") {
            let p = raw.dropFirst().split(separator: "-", maxSplits: 1)
            guard let country = p.first else { return nil }
            return sites["\(country)|\(p.count == 2 ? String(p[1]) : "")"]
        }
        return sites["\(entry.country)|\(raw)"]
    }
    public static func parse(_ text: String) -> Self {
        var result = Self(), section = 0, country = ""
        let row = try! NSRegularExpression(pattern: "^\\s{3}([A-Za-z0-9-]+)\\s{2,}(.+)$")
        let targetRow = try! NSRegularExpression(pattern: "^\\s{3}([A-Za-z.]+)\\s+-\\s+(.+)$")
        let coordinate = try! NSRegularExpression(pattern: "(\\d{1,2})([NS])(\\d{2})(?:'(\\d{2})\")?-(\\d{1,3})([EW])(\\d{2})(?:'(\\d{2})\")?")
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "I) Language codes." { section = 1; continue }
            if trimmed == "II) Country codes." { section = 2; continue }
            if trimmed == "III) Target-area codes." { section = 3; continue }
            if trimmed == "IV) Transmitter site codes." { section = 4; continue }
            if section < 4, let m = row.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let a = Range(m.range(at: 1), in: line), let b = Range(m.range(at: 2), in: line) {
                let key = String(line[a]), value = String(line[b]).trimmingCharacters(in: .whitespaces)
                if section == 1 { result.languages[key] = value }
                if section == 2 { result.countries[key] = value }
                if section == 3 { result.targets[key] = value.hasPrefix("- ") ? String(value.dropFirst(2)) : value }
            }
            if section == 3, let m = targetRow.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let a = Range(m.range(at: 1), in: line), let b = Range(m.range(at: 2), in: line) { result.targets[String(line[a])] = String(line[b]) }
            guard section == 4 else { continue }
            var content = trimmed
            if let colon = content.firstIndex(of: ":") {
                let code = String(content[..<colon])
                if code.count <= 3 && code.allSatisfy({ $0.isUppercase || $0.isNumber }) { country = code; content = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
            }
            let matches = coordinate.matches(in: content, range: NSRange(content.startIndex..., in: content))
            guard !country.isEmpty, matches.count == 1, let m = matches.first, let location = Range(m.range, in: content) else { continue }
            func group(_ index: Int) -> String { Range(m.range(at: index), in: content).map { String(content[$0]) } ?? "" }
            func angle(_ degrees: Int, _ minutes: Int, _ seconds: Int) -> Double { (Double(group(degrees)) ?? 0) + (Double(group(minutes)) ?? 0)/60 + (Double(group(seconds)) ?? 0)/3600 }
            let lat = angle(1,3,4) * (group(2) == "S" ? -1 : 1)
            let lon = angle(5,7,8) * (group(6) == "W" ? -1 : 1)
            guard abs(lat) <= 90, abs(lon) <= 180 else { continue }
            var name = String(content[..<location.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), code = ""
            if let dash = name.firstIndex(of: "-"), name[..<dash].count <= 3, name[..<dash].allSatisfy({ $0.isLetter }) { code = String(name[..<dash]); name = String(name[name.index(after: dash)...]) }
            result.sites["\(country)|\(code)"] = BroadcastSite(name: name, latitude: lat, longitude: lon)
        }
        return result
    }
}
