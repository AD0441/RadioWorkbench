import Foundation
import SatelliteKit

/// Amateur allocations published by SUBTEL in its 2025 band table.
public struct ChileBandAllocation: Identifiable, Hashable, Sendable {
    public let lowerMHz: Double
    public let upperMHz: Double
    public let service: String
    public let status: String
    public let satellite: Bool
    public var id: String { "\(lowerMHz)-\(upperMHz)-\(service)-\(satellite)" }

    public init(lowerMHz: Double, upperMHz: Double, service: String = "Aficionado", status: String, satellite: Bool = false) {
        self.lowerMHz = lowerMHz; self.upperMHz = upperMHz; self.service = service; self.status = status; self.satellite = satellite
    }

    public static let source = URL(string: "https://www.subtel.gob.cl/wp-content/uploads/2025/06/Tabla_de_Bandas_Actualizada_2025.pdf")!
    public static let updatedAt = "2025-06"
    public static let all: [ChileBandAllocation] = [
        .init(lowerMHz: 0.1357, upperMHz: 0.1378, status: "Secundario"),
        .init(lowerMHz: 0.472, upperMHz: 0.479, status: "Secundario"),
        .init(lowerMHz: 1.8, upperMHz: 1.85, status: "Primario"),
        .init(lowerMHz: 3.5, upperMHz: 3.75, status: "Primario"),
        .init(lowerMHz: 5.3515, upperMHz: 5.3665, status: "Primario"),
        .init(lowerMHz: 7.0, upperMHz: 7.1, status: "Primario"),
        .init(lowerMHz: 7.1, upperMHz: 7.3, status: "Primario"),
        .init(lowerMHz: 10.1, upperMHz: 10.125, status: "Secundario"),
        .init(lowerMHz: 10.1, upperMHz: 10.15, status: "Primario"),
        .init(lowerMHz: 14.0, upperMHz: 14.25, status: "Primario"),
        .init(lowerMHz: 14.25, upperMHz: 14.35, status: "Primario"),
        .init(lowerMHz: 18.068, upperMHz: 18.168, status: "Primario"),
        .init(lowerMHz: 21.0, upperMHz: 21.45, status: "Primario"),
        .init(lowerMHz: 24.89, upperMHz: 24.99, status: "Primario"),
        .init(lowerMHz: 28.0, upperMHz: 29.7, status: "Primario"),
        .init(lowerMHz: 50.0, upperMHz: 54.0, status: "Primario"),
        .init(lowerMHz: 144.0, upperMHz: 146.0, status: "Primario"),
        .init(lowerMHz: 144.0, upperMHz: 146.0, service: "Aficionado por satélite", status: "Primario", satellite: true),
        .init(lowerMHz: 146.0, upperMHz: 148.0, status: "Primario"),
        .init(lowerMHz: 220.0, upperMHz: 225.0, status: "Primario"),
        .init(lowerMHz: 430.0, upperMHz: 432.0, status: "Secundario"),
        .init(lowerMHz: 432.0, upperMHz: 438.0, status: "Secundario"),
        .init(lowerMHz: 438.0, upperMHz: 440.0, status: "Secundario"),
        .init(lowerMHz: 1240.0, upperMHz: 1300.0, status: "Secundario"),
        .init(lowerMHz: 2400.0, upperMHz: 2450.0, status: "Secundario"),
        .init(lowerMHz: 3300.0, upperMHz: 3400.0, status: "Primario"),
        .init(lowerMHz: 3300.0, upperMHz: 3400.0, status: "Secundario"),
        .init(lowerMHz: 5650.0, upperMHz: 5725.0, status: "Secundario"),
        .init(lowerMHz: 5725.0, upperMHz: 5830.0, status: "Secundario"),
        .init(lowerMHz: 5830.0, upperMHz: 5850.0, status: "Secundario"),
        .init(lowerMHz: 5830.0, upperMHz: 5850.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 10450.0, upperMHz: 10500.0, status: "Secundario"),
        .init(lowerMHz: 10450.0, upperMHz: 10500.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 24000.0, upperMHz: 24050.0, status: "Primario"),
        .init(lowerMHz: 24000.0, upperMHz: 24050.0, service: "Aficionado por satélite", status: "Primario", satellite: true),
        .init(lowerMHz: 24050.0, upperMHz: 24250.0, status: "Secundario"),
        .init(lowerMHz: 47000.0, upperMHz: 47200.0, status: "Primario"),
        .init(lowerMHz: 47000.0, upperMHz: 47200.0, service: "Aficionado por satélite", status: "Primario", satellite: true),
        .init(lowerMHz: 76000.0, upperMHz: 77500.0, status: "Secundario"),
        .init(lowerMHz: 76000.0, upperMHz: 77500.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 77500.0, upperMHz: 78000.0, status: "Primario", satellite: true),
        .init(lowerMHz: 78000.0, upperMHz: 79000.0, status: "Secundario"),
        .init(lowerMHz: 78000.0, upperMHz: 79000.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 79000.0, upperMHz: 81000.0, status: "Secundario"),
        .init(lowerMHz: 79000.0, upperMHz: 81000.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 122250.0, upperMHz: 123000.0, status: "Secundario"),
        .init(lowerMHz: 134000.0, upperMHz: 136000.0, status: "Primario", satellite: true),
        .init(lowerMHz: 136000.0, upperMHz: 141000.0, status: "Secundario"),
        .init(lowerMHz: 136000.0, upperMHz: 141000.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 241000.0, upperMHz: 248000.0, status: "Secundario"),
        .init(lowerMHz: 241000.0, upperMHz: 248000.0, service: "Aficionado por satélite", status: "Secundario", satellite: true),
        .init(lowerMHz: 248000.0, upperMHz: 250000.0, status: "Primario", satellite: true)
    ]

    public static func matches(_ frequencyMHz: Double) -> [Self] {
        all.filter { frequencyMHz >= $0.lowerMHz && frequencyMHz <= $0.upperMHz }
    }
}

public struct RadioPosition: Hashable, Sendable, Identifiable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let symbol: String
    public let comment: String
    public let path: String
    public let receivedAt: Date

    public init(id: String, latitude: Double, longitude: Double, symbol: String, comment: String, path: String, receivedAt: Date = Date()) {
        self.id = id; self.latitude = latitude; self.longitude = longitude; self.symbol = symbol
        self.comment = comment; self.path = path; self.receivedAt = receivedAt
    }
}

public struct VHFRepeater: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let region: String
    public let comuna: String
    public let receiveMHz: Double?
    public let transmitMHz: Double?
    public let toneHz: Double?
    public let latitude: Double?
    public let longitude: Double?
    public let detail: String

    public init(id: String, region: String = "", comuna: String = "", receiveMHz: Double? = nil, transmitMHz: Double? = nil,
                toneHz: Double? = nil, latitude: Double? = nil, longitude: Double? = nil, detail: String = "") {
        self.id = id.uppercased(); self.region = region; self.comuna = comuna; self.receiveMHz = receiveMHz
        self.transmitMHz = transmitMHz; self.toneHz = toneHz; self.latitude = latitude; self.longitude = longitude; self.detail = detail
    }
}

public enum SUBTELRepeaterParser {
    /// Parses a table after its XLSX rows have been extracted. Header matching is deliberately tolerant
    /// because SUBTEL may rename columns between monthly reports.
    public static func parse(rows: [[String]]) -> [VHFRepeater] {
        guard !rows.isEmpty else { return [] }
        let headerIndex = rows.prefix(25).firstIndex { row in row.contains { value in
            let key = normalize(value)
            return key.contains("indicativo") || key.contains("senal distintiva") || key.contains("callsign") || key == "senal"
        } } ?? 0
        let headers = rows[headerIndex].map(normalize)
        func column(_ tests: [(String) -> Bool]) -> Int? { headers.firstIndex { key in tests.contains { $0(key) } } }
        let callColumn = column([{ $0.contains("indicativo") }, { $0.contains("senal distintiva") }, { $0.contains("callsign") }, { $0 == "senal" }])
        guard let callColumn else { return [] }
        let regionColumn = column([{ $0 == "region" }, { $0.contains("region") }])
        let comunaColumn = column([{ $0.contains("comuna") }, { $0.contains("localidad") }])
        let receiveColumn = column([{ $0.contains("frecuencia") && ($0.contains("recepcion") || $0.contains("entrada") || $0.contains("rx")) }, { $0 == "rx" || $0.hasPrefix("rx ") }, { $0.contains("frecuencia de entrada") }])
        let transmitColumn = column([{ $0.contains("frecuencia") && ($0.contains("transmision") || $0.contains("salida") || $0.contains("tx")) }, { $0 == "tx" || $0.hasPrefix("tx ") }, { $0.contains("frecuencia de salida") }])
        let toneColumn = column([{ $0.contains("tono") || $0.contains("ctcss") }])
        let latitudeColumn = column([{ $0 == "latitud" }, { $0 == "latitude" }, { $0 == "lat" }])
        let longitudeColumn = column([{ $0 == "longitud" }, { $0 == "longitude" }, { $0 == "lon" }, { $0 == "long" }])
        let detailColumns = headers.indices.filter { index in
            headers[index].contains("modo") || headers[index].contains("potencia") || headers[index].contains("fecha") || headers[index].contains("estado")
        }
        return rows.dropFirst(headerIndex + 1).compactMap { row in
            guard let call = value(row, callColumn), call.range(of: #"^[A-Za-z0-9/-]{3,20}$"#, options: .regularExpression) != nil else { return nil }
            let lat = latitudeColumn.flatMap { value(row, $0) }.flatMap(parseCoordinate)
            let lon = longitudeColumn.flatMap { value(row, $0) }.flatMap(parseCoordinate)
            let detail = detailColumns.compactMap { index in value(row, index).map { "\(rows[headerIndex][index]): \($0)" } }.joined(separator: " · ")
            return VHFRepeater(id: call, region: regionColumn.flatMap { value(row, $0) } ?? "", comuna: comunaColumn.flatMap { value(row, $0) } ?? "",
                               receiveMHz: receiveColumn.flatMap { value(row, $0) }.flatMap(parseFrequencyMHz),
                               transmitMHz: transmitColumn.flatMap { value(row, $0) }.flatMap(parseFrequencyMHz),
                               toneHz: toneColumn.flatMap { value(row, $0) }.flatMap(parseNumber), latitude: lat, longitude: lon, detail: detail)
        }
    }

    private static func value(_ row: [String], _ index: Int) -> String? {
        guard row.indices.contains(index) else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "-" ? nil : value
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "º", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func parseNumber(_ value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard let number = Double(normalized), number.isFinite, number >= 0 else { return nil }
        return number
    }
    private static func parseFrequencyMHz(_ value: String) -> Double? {
        guard let number = parseNumber(value) else { return nil }
        // SUBTEL reports may use MHz, kHz, or Hz columns depending on the export.
        if number >= 1_000_000 { return number / 1_000_000 }
        return number >= 1_000 ? number / 1_000 : number
    }
    private static func parseCoordinate(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
        if let direct = Double(normalized), direct.isFinite, abs(direct) <= 180 { return direct }
        let numberRegex = try? NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#)
        let numberRanges = numberRegex?.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap { Range($0.range, in: normalized) } ?? []
        let parts = numberRanges.compactMap { Double(normalized[$0]) }
        if parts.count == 1, let degrees = parts.first {
            let sign = (normalized.localizedCaseInsensitiveContains("S") || normalized.localizedCaseInsensitiveContains("W") || degrees < 0) ? -1.0 : 1.0
            return sign * abs(degrees)
        }
        if let degrees = parts.first, parts.count >= 2, parts[1] < 60 {
            let seconds = parts.count > 2 && parts[2] < 60 ? parts[2] : 0
            let sign = (normalized.localizedCaseInsensitiveContains("S") || normalized.localizedCaseInsensitiveContains("W") || degrees < 0) ? -1.0 : 1.0
            return sign * (abs(degrees) + parts[1] / 60 + seconds / 3600)
        }
        return nil
    }
}

public struct LicensedCallsign: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let category: String
    public let region: String
    public let expiresOn: String
    public init(id: String, category: String, region: String, expiresOn: String) {
        self.id = id.uppercased(); self.category = category; self.region = region; self.expiresOn = expiresOn
    }
}

public enum SUBTELCallsignParser {
    /// Only retains callsign, license category, region and expiration date from SUBTEL's public roster text.
    public static func parse(_ text: String, category: String) -> [LicensedCallsign] {
        var records: [LicensedCallsign] = []
        for line in text.components(separatedBy: .newlines) {
            guard let match = line.range(of: #"\b([A-Z]{1,3}[0-9][A-Z]{1,4})\b.*?\b(Región[^0-9]+?)\s+(\d{2}/\d{2}/\d{4})\s*$"#, options: [.regularExpression, .caseInsensitive]) else { continue }
            let row = String(line[match])
            guard let callRange = row.range(of: #"\b[A-Z]{1,3}[0-9][A-Z]{1,4}\b"#, options: .regularExpression),
                  let dateRange = row.range(of: #"\d{2}/\d{2}/\d{4}$"#, options: .regularExpression) else { continue }
            let call = String(row[callRange]).uppercased()
            let date = String(row[dateRange])
            let middle = String(row[callRange.upperBound..<dateRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let region = middle.components(separatedBy: "Región").dropFirst().joined(separator: "Región").trimmingCharacters(in: .whitespaces)
            guard !call.isEmpty else { continue }
            records.append(LicensedCallsign(id: call, category: category, region: region, expiresOn: date))
        }
        return Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { old, new in old.expiresOn >= new.expiresOn ? old : new }).values.sorted { $0.id < $1.id }
    }
}

public struct AmateurSatelliteTransmitter: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let noradID: String?
    public let uplink: String?
    public let downlink: String?
    public let beacon: String?
    public let mode: String?
    public let callsign: String?
    public var id: String { "\(name)-\(uplink ?? "")-\(downlink ?? "")-\(mode ?? "")" }

    enum CodingKeys: String, CodingKey {
        case name, uplink, downlink, beacon, mode, callsign
        case noradID = "norad_id"
    }
}

public enum APRSPositionParser {
    /// Parses uncompressed APRS position reports, including current position objects.
    /// Compressed positions and Mic-E are intentionally left to a full AX.25 decoder.
    public static func parse(_ packet: String, receivedAt: Date = Date()) -> RadioPosition? {
        guard let separator = packet.firstIndex(of: ":") else { return nil }
        let header = String(packet[..<separator])
        guard let source = header.split(separator: ">", maxSplits: 1).first, !source.isEmpty else { return nil }
        let body = String(packet[packet.index(after: separator)...])
        let bytes = Array(body.utf8)
        guard let marker = bytes.first, [UInt8(33), 61, 47, 64, 59].contains(marker) else { return nil }
        var start = 1
        var objectID = String(source)
        if marker == 47 || marker == 64 { start += 7 } // timestamp before a position
        if marker == 59 { // ;object-name*DDHHMMz followed by uncompressed position
            guard bytes.count >= 19 else { return nil }
            objectID = String(decoding: bytes[1..<10], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            start = 18
        }
        let path = header.split(separator: ">", maxSplits: 1).last.map(String.init) ?? ""
        if bytes.count >= start + 19 {
            let latitudeBytes = Array(bytes[start..<(start + 8)])
            let longitudeBytes = Array(bytes[(start + 9)..<(start + 18)])
            let looksUncompressed = latitudeBytes[4] == 46 && longitudeBytes[5] == 46
                && [UInt8(78), 83].contains(latitudeBytes[7])
                && [UInt8(69), 87].contains(longitudeBytes[8])
            let lat = Self.coordinate(latitudeBytes, degreeDigits: 2, positive: 78, negative: 83)
            let table = bytes[start + 8]
            let lon = Self.coordinate(longitudeBytes, degreeDigits: 3, positive: 69, negative: 87)
            if let lat, let lon, (-90...90).contains(lat), (-180...180).contains(lon) {
                let symbol = String(decoding: [table, bytes[start + 18]], as: UTF8.self)
                let commentStart = start + 19
                let comment = commentStart < bytes.count ? String(decoding: bytes[commentStart...], as: UTF8.self) : ""
                return RadioPosition(id: objectID, latitude: lat, longitude: lon, symbol: symbol, comment: comment, path: path, receivedAt: receivedAt)
            }
            if looksUncompressed { return nil }
        }
        return Self.parseCompressed(bytes, start: start, id: objectID, path: path, receivedAt: receivedAt)
    }

    private static func coordinate(_ bytes: [UInt8], degreeDigits: Int, positive: UInt8, negative: UInt8) -> Double? {
        guard bytes.count == degreeDigits + 6, let hemisphere = bytes.last,
              hemisphere == positive || hemisphere == negative else { return nil }
        let degreeString = String(decoding: bytes.prefix(degreeDigits), as: UTF8.self)
        let minuteString = String(decoding: bytes[degreeDigits..<(bytes.count - 1)], as: UTF8.self)
        guard let degrees = Double(degreeString), let minutes = Double(minuteString), minutes < 60 else { return nil }
        return (hemisphere == negative ? -1 : 1) * (degrees + minutes / 60)
    }

    private static func parseCompressed(_ bytes: [UInt8], start: Int, id: String, path: String, receivedAt: Date) -> RadioPosition? {
        guard bytes.count >= start + 10 else { return nil }
        let latitudeValue = base91(Array(bytes[(start + 1)..<(start + 5)]))
        let longitudeValue = base91(Array(bytes[(start + 5)..<(start + 9)]))
        guard let latitudeValue, let longitudeValue else { return nil }
        let latitude = 90 - Double(latitudeValue) / 380_926
        let longitude = -180 + Double(longitudeValue) / 190_463
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let symbol = String(decoding: [bytes[start], bytes[start + 9]], as: UTF8.self)
        let commentStart = min(bytes.count, start + 14)
        let comment = commentStart < bytes.count ? String(decoding: bytes[commentStart...], as: UTF8.self) : ""
        return RadioPosition(id: id, latitude: latitude, longitude: longitude, symbol: symbol, comment: comment, path: path, receivedAt: receivedAt)
    }

    private static func base91(_ bytes: [UInt8]) -> Int? {
        guard bytes.count == 4, bytes.allSatisfy({ (33...123).contains($0) }) else { return nil }
        return bytes.reduce(0) { $0 * 91 + Int($1 - 33) }
    }
}

public struct TLEOrbit: Codable, Hashable, Sendable {
    public let name: String
    public let catalogNumber: Int
    public let epoch: Date
    public let meanMotionRevolutionsPerDay: Double
    public let eccentricity: Double
    public let inclinationDegrees: Double
    public let raanDegrees: Double
    public let argumentOfPerigeeDegrees: Double
    public let meanAnomalyDegrees: Double
    public let bstar: Double?

    public init(name: String, catalogNumber: Int, epoch: Date, meanMotionRevolutionsPerDay: Double, eccentricity: Double,
                inclinationDegrees: Double, raanDegrees: Double, argumentOfPerigeeDegrees: Double, meanAnomalyDegrees: Double, bstar: Double? = 0) {
        self.name = name; self.catalogNumber = catalogNumber; self.epoch = epoch
        self.meanMotionRevolutionsPerDay = meanMotionRevolutionsPerDay; self.eccentricity = eccentricity
        self.inclinationDegrees = inclinationDegrees; self.raanDegrees = raanDegrees
        self.argumentOfPerigeeDegrees = argumentOfPerigeeDegrees; self.meanAnomalyDegrees = meanAnomalyDegrees; self.bstar = bstar
    }

    public var isValid: Bool {
        let values = [meanMotionRevolutionsPerDay, eccentricity, inclinationDegrees, raanDegrees, argumentOfPerigeeDegrees, meanAnomalyDegrees]
        return catalogNumber > 0 && epoch.timeIntervalSince1970.isFinite && values.allSatisfy(\.isFinite)
            && meanMotionRevolutionsPerDay > 0 && meanMotionRevolutionsPerDay <= 20
            && (0..<1).contains(eccentricity) && (0...180).contains(inclinationDegrees)
            && (0...360).contains(raanDegrees) && (0...360).contains(argumentOfPerigeeDegrees) && (0...360).contains(meanAnomalyDegrees)
    }

    /// Legacy caches lacking BSTAR must be refreshed before SGP4 propagation.
    public var propagationReady: Bool { isValid && bstar?.isFinite == true }

    public func position(at date: Date) -> SatellitePosition? {
        guard let p = earthFixedPosition(at: date) else { return nil }
        let r = hypot(p.x, p.y), e2 = 0.00669437999014
        var lat = atan2(p.z, r * (1 - e2))
        for _ in 0..<12 {
            let n = 6378.137 / sqrt(1 - e2 * pow(sin(lat), 2))
            lat = atan2(p.z + e2 * n * sin(lat), r)
        }
        let n = 6378.137 / sqrt(1 - e2 * pow(sin(lat), 2))
        let altitude = r > 1e-8 ? r / cos(lat) - n : abs(p.z) - 6356.752314245
        return SatellitePosition(latitude: lat * 180 / .pi, longitude: atan2(p.y, p.x) * 180 / .pi, altitudeKm: altitude)
    }

    public func observation(at date: Date, latitude: Double, longitude: Double) -> SatelliteObservation? {
        guard RadioLocation(latitude: latitude, longitude: longitude) != nil,
              let p = earthFixedPosition(at: date), let before = earthFixedPosition(at: date.addingTimeInterval(-0.5)),
              let after = earthFixedPosition(at: date.addingTimeInterval(0.5)) else { return nil }
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180
        let sinLat = sin(lat), cosLat = cos(lat), e2 = 0.00669437999014
        let n = 6378.137 / sqrt(1 - e2 * sinLat * sinLat)
        let dx = p.x - n * cosLat * cos(lon), dy = p.y - n * cosLat * sin(lon), dz = p.z - n * (1 - e2) * sinLat
        let east = -sin(lon) * dx + cos(lon) * dy
        let north = -sinLat * cos(lon) * dx - sinLat * sin(lon) * dy + cosLat * dz
        let up = cosLat * cos(lon) * dx + cosLat * sin(lon) * dy + sinLat * dz
        let range = sqrt(dx * dx + dy * dy + dz * dz)
        guard range > 0 else { return nil }
        return SatelliteObservation(azimuthDegrees: (atan2(east, north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360),
            elevationDegrees: atan2(up, hypot(east, north)) * 180 / .pi, rangeKm: range,
            rangeRateKmPerSecond: (dx * (after.x - before.x) + dy * (after.y - before.y) + dz * (after.z - before.z)) / range)
    }

    public func elevationDegrees(at date: Date, latitude: Double, longitude: Double) -> Double? {
        observation(at: date, latitude: latitude, longitude: longitude)?.elevationDegrees
    }

    public func temePosition(at date: Date) -> (x: Double, y: Double, z: Double)? {
        guard propagationReady, date.timeIntervalSince1970.isFinite, let bstar else { return nil }
        let elements = Elements(commonName: name, noradIndex: UInt(catalogNumber), launchName: "", t₀: epoch,
            e₀: eccentricity, i₀: inclinationDegrees, ω₀: argumentOfPerigeeDegrees, Ω₀: raanDegrees,
            M₀: meanAnomalyDegrees, n₀: meanMotionRevolutionsPerDay, ephemType: 0, tleClass: "U", tleNumber: 0, revNumber: 0, dragCoeff: bstar)
        guard let p = try? Satellite(elements: elements).position(minsAfterEpoch: date.timeIntervalSince(epoch) / 60),
              p.x.isFinite, p.y.isFinite, p.z.isFinite else { return nil }
        return (p.x, p.y, p.z)
    }
    private func earthFixedPosition(at date: Date) -> (x: Double, y: Double, z: Double)? {
        guard let p = temePosition(at: date) else { return nil }
        let theta = Self.greenwichSiderealAngle(at: date)
        return (cos(theta) * p.x + sin(theta) * p.y, -sin(theta) * p.x + cos(theta) * p.y, p.z)
    }

    private static func greenwichSiderealAngle(at date: Date) -> Double {
        let julianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDate - 2_451_545.0) / 36_525
        let degrees = 280.46061837 + 360.98564736629 * (julianDate - 2_451_545.0) + 0.000387933 * t * t - t * t * t / 38_710_000
        return degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
    }
}

public struct SatellitePass: Hashable, Sendable, Identifiable {
    public let satellite: String
    public let aos: Date
    public let maximumElevation: Double
    public let maximumAt: Date
    public let los: Date
    public var id: String { "\(satellite)-\(aos.timeIntervalSince1970)" }
}

public enum SatellitePassPredictor {
    public static func passes(orbit: TLEOrbit, latitude: Double, longitude: Double, from start: Date,
                              hours: Int = 24, stepSeconds: TimeInterval = 20, minimumPeak: Double = 5) -> [SatellitePass] {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude), (1...72).contains(hours), stepSeconds >= 2 else { return [] }
        let end = start.addingTimeInterval(TimeInterval(hours) * 3600)
        var samples: [(Date, Double)] = []
        var date = start
        while date <= end {
            if let elevation = orbit.elevationDegrees(at: date, latitude: latitude, longitude: longitude) { samples.append((date, elevation)) }
            date = date.addingTimeInterval(stepSeconds)
        }
        guard samples.count > 2 else { return [] }
        var results: [SatellitePass] = []
        var rising: Date?
        var peak = -90.0
        var peakAt = start
        for index in samples.indices {
            let (time, elevation) = samples[index]
            if elevation >= 0 {
                if rising == nil {
                    let previous = samples[max(0, index - 1)]
                    rising = Self.crossing(previous, (time, elevation), threshold: 0)
                    peak = elevation; peakAt = time
                } else if elevation > peak { peak = elevation; peakAt = time }
            } else if let aos = rising {
                let previous = samples[max(0, index - 1)]
                let los = Self.crossing(previous, (time, elevation), threshold: 0)
                if peak >= minimumPeak, los > aos { results.append(SatellitePass(satellite: orbit.name, aos: aos, maximumElevation: peak, maximumAt: peakAt, los: los)) }
                rising = nil; peak = -90
            }
        }
        return results
    }

    private static func crossing(_ a: (Date, Double), _ b: (Date, Double), threshold: Double) -> Date {
        let delta = b.1 - a.1
        guard abs(delta) > 0.0001 else { return a.0 }
        let fraction = min(1, max(0, (threshold - a.1) / delta))
        return a.0.addingTimeInterval(b.0.timeIntervalSince(a.0) * fraction)
    }
}
