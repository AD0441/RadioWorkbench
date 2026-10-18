import Foundation

public enum RadioNumericText {
    public static func number(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: ".")
        guard let result = Double(value), result.isFinite else { return nil }
        return result
    }
    /// Unitless input is MHz; explicit units prevent accidental kHz/MHz copies.
    public static func frequencyMHz(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (suffix, scale) in [("mhz", 1.0), ("khz", 0.001), ("hz", 0.000001)] where value.hasSuffix(suffix) {
            return number(String(value.dropLast(suffix.count))).map { $0 * scale }
        }
        return number(value)
    }
}

public struct RadioLocation: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        self.latitude = latitude; self.longitude = longitude
    }
    public init?(latitude: String, longitude: String) {
        guard let lat = RadioNumericText.number(latitude), let lon = RadioNumericText.number(longitude) else { return nil }
        self.init(latitude: lat, longitude: lon)
    }
    public func distance(to other: Self) -> Double {
        let a = latitude * .pi / 180, b = other.latitude * .pi / 180
        let dlat = b - a, dlon = (other.longitude - longitude) * .pi / 180
        let h = pow(sin(dlat / 2), 2) + cos(a) * cos(b) * pow(sin(dlon / 2), 2)
        return 6371 * 2 * asin(sqrt(min(1, max(0, h))))
    }
    public func bearing(to other: Self) -> Double {
        let a = latitude * .pi / 180, b = other.latitude * .pi / 180
        let dlon = (other.longitude - longitude) * .pi / 180
        let angle = atan2(sin(dlon) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(dlon)) * 180 / .pi
        return (angle + 360).truncatingRemainder(dividingBy: 360)
    }
    public func destination(km: Double, bearing: Double) -> Self? {
        guard km.isFinite, km >= 0, km <= 20_000, bearing.isFinite else { return nil }
        let a = latitude * .pi / 180, l = longitude * .pi / 180, t = bearing * .pi / 180, d = km / 6371
        let b = asin(min(1, max(-1, sin(a) * cos(d) + cos(a) * sin(d) * cos(t))))
        let lon = l + atan2(sin(t) * sin(d) * cos(a), cos(d) - sin(a) * sin(b))
        return Self(latitude: b * 180 / .pi, longitude: (lon * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
    /// Approximate geometric solar elevation, NOAA fractional-year equations; no refraction correction.
    public func solarElevation(at date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .hour, .minute, .second], from: date)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let days = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let g = 2 * Double.pi / Double(days) * (Double(day - 1) + (hour - 12) / 24)
        let eq = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2*g) - 0.040849 * sin(2*g))
        let dec = 0.006918 - 0.399912*cos(g) + 0.070257*sin(g) - 0.006758*cos(2*g) + 0.000907*sin(2*g) - 0.002697*cos(3*g) + 0.00148*sin(3*g)
        let angle = (hour * 60 + eq + 4 * longitude) / 4 * .pi / 180 - .pi
        let lat = latitude * .pi / 180
        return asin(min(1, max(-1, sin(lat)*sin(dec) + cos(lat)*cos(dec)*cos(angle)))) * 180 / .pi
    }
}

public enum RadioLinkBudget {
    public static func powerDifference(watts: Double, referenceWatts: Double) -> Double? {
        guard watts.isFinite, referenceWatts.isFinite, watts > 0, referenceWatts > 0 else { return nil }
        return 10 * log10(watts / referenceWatts)
    }
    /// Smooth-Earth radio horizon with explicitly assumed effective Earth radius k = 4/3.
    public static func horizonKm(txHeight: Double, rxHeight: Double, k: Double = 4.0/3) -> Double? {
        guard txHeight.isFinite, rxHeight.isFinite, k.isFinite, txHeight >= 0, rxHeight >= 0, k > 0 else { return nil }
        return sqrt(2 * 6371 * k * txHeight / 1000) + sqrt(2 * 6371 * k * rxHeight / 1000)
    }
}

public struct HFBand: Identifiable, Sendable {
    public let name: String
    public let frequencyMHz: Double
    public var id: String { name }
    public static let all: [Self] = [
        .init(name: "160 m", frequencyMHz: 1.8), .init(name: "80 m", frequencyMHz: 3.6),
        .init(name: "60 m", frequencyMHz: 5.3), .init(name: "40 m", frequencyMHz: 7.1),
        .init(name: "30 m", frequencyMHz: 10.1), .init(name: "20 m", frequencyMHz: 14.1),
        .init(name: "17 m", frequencyMHz: 18.1), .init(name: "15 m", frequencyMHz: 21.1),
        .init(name: "12 m", frequencyMHz: 24.9), .init(name: "10 m", frequencyMHz: 28.2)
    ]
}
