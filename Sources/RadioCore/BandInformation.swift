import Foundation

public enum BandCondition: String, Codable, Sendable {
    case good = "Good", fair = "Fair", poor = "Poor"
    public var title: String { switch self { case .good: "Buena"; case .fair: "Regular"; case .poor: "Baja" } }
}
public struct BandInformation: Codable, Sendable, Identifiable {
    public let name: String
    public let day: BandCondition
    public let night: BandCondition
    public var id: String { name }
}
public struct RegionalVHFInformation: Codable, Sendable, Identifiable {
    public let phenomenon: String
    public let region: String
    public let status: String
    public var id: String { phenomenon + ":" + region }
    public var regionTitle: String {
        switch region {
        case "northern_hemi": "Hemisferio norte"
        case "north_america": "Norteamérica"
        case "europe": "Europa"
        case "europe_6m": "Europa · 6 m"
        case "europe_4m": "Europa · 4 m"
        default: region
        }
    }
    public var statusTitle: String {
        switch status.lowercased() { case "band closed": "Sin apertura reportada"; case "band open": "Apertura reportada"; default: status }
    }
}
public struct BandInformationSnapshot: Codable, Sendable {
    public let bands: [BandInformation]
    public let vhf: [RegionalVHFInformation]
    public let updatedAt: Date
    public let fetchedAt: Date
    public func isFresh(at date: Date) -> Bool { (-300...6*3600).contains(date.timeIntervalSince(updatedAt)) }
    public func changes(from old: Self) -> [String] {
        guard updatedAt > old.updatedAt else { return [] }
        return bands.flatMap { row -> [String] in
            guard let previous = old.bands.first(where: { $0.name == row.name }) else { return [] }
            var messages: [String] = []
            if previous.day != row.day { messages.append("\(row.name) · día: \(previous.day.title) → \(row.day.title)") }
            if previous.night != row.night { messages.append("\(row.name) · noche: \(previous.night.title) → \(row.night.title)") }
            return messages
        }
    }
}

private final class BandXMLReader: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    var bands: [String: [String: BandCondition]] = [:]
    var vhf: [RegionalVHFInformation] = []
    var text = ""
    var attributes: [String: String] = [:]
    var path: [String] = []
    var invalid = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String]) {
        path.append(name); text = ""; attributes = attributeDict
        if path.count > 8 { invalid = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
        if text.utf8.count > 1024 { invalid = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == ["solar", "solardata", "calculatedconditions", "band"] {
            if let band = attributes["name"], ["80m-40m", "30m-20m", "17m-15m", "12m-10m"].contains(band),
               let time = attributes["time"], ["day", "night"].contains(time), let condition = BandCondition(rawValue: value), bands[band]?[time] == nil {
                bands[band, default: [:]][time] = condition
            } else { invalid = true }
        } else if path == ["solar", "solardata", "calculatedvhfconditions", "phenomenon"] {
            if let name = attributes["name"], let region = attributes["location"], name.count < 50, region.count < 50, value.count < 100, vhf.count < 20 {
                vhf.append(RegionalVHFInformation(phenomenon: name, region: region, status: value))
            } else { invalid = true }
        } else if path.count == 3 { values[name] = value }
        if !path.isEmpty { path.removeLast() }
    }
}

public enum BandInformationParser {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> BandInformationSnapshot {
        guard data.count <= 65_536, let xml = String(data: data, encoding: .utf8),
              !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY") else { throw URLError(.cannotParseResponse) }
        let parser = XMLParser(data: data), reader = BandXMLReader()
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), !reader.invalid, let stamp = reader.values["updated"] else { throw URLError(.cannotParseResponse) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "d MMM yyyy HHmm 'GMT'"
        guard let time = f.date(from: stamp), time <= fetchedAt.addingTimeInterval(300) else { throw URLError(.cannotParseResponse) }
        let rows = ["80m-40m", "30m-20m", "17m-15m", "12m-10m"].compactMap { name -> BandInformation? in
            guard let day = reader.bands[name]?["day"], let night = reader.bands[name]?["night"] else { return nil }
            return BandInformation(name: name, day: day, night: night)
        }
        guard rows.count == 4, Set(reader.vhf.map(\.id)).count == reader.vhf.count else { throw URLError(.cannotParseResponse) }
        return BandInformationSnapshot(bands: rows, vhf: reader.vhf, updatedAt: time, fetchedAt: fetchedAt)
    }
}

public enum RadioContactDistance: String, CaseIterable, Sendable {
    case nearby = "Cercano", regional = "Regional", distant = "Lejano", dx = "DX lejano"
    public static func classify(km: Double) -> Self? {
        guard km.isFinite, km >= 0 else { return nil }
        switch km.rounded() { case ...100: return .nearby; case ...1000: return .regional; case ...5000: return .distant; default: return .dx }
    }
    public static func international(originCountry: String, targetCountry: String) -> Bool? {
        let a = originCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let b = targetCountry.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regions = Set(Locale.Region.isoRegions.map(\.identifier))
        guard a.count == 2, b.count == 2, regions.contains(a), regions.contains(b) else { return nil }
        return a != b
    }
}
