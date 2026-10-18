import Foundation

public enum MT63Variant: String, CaseIterable, Codable, Sendable, Identifiable {
    case b500Short, b500Long, b1000Short, b1000Long, b2000Short, b2000Long
    public var id: String { rawValue }
    public var bandwidth: Int {
        switch self { case .b500Short, .b500Long: 500; case .b1000Short, .b1000Long: 1000; case .b2000Short, .b2000Long: 2000 }
    }
    public var interleave: String {
        switch self { case .b500Short, .b1000Short, .b2000Short: "short"; default: "long" }
    }
    public var title: String { "\(bandwidth) Hz · entrelazado \(interleave == "long" ? "largo" : "corto")" }
    public var fixtureName: String { "mt63_\(bandwidth)_\(interleave)_8000_clean" }
}

public enum PagerRate: String, CaseIterable, Codable, Sendable, Identifiable {
    case automatic, bps512, bps1200, bps2400
    public var id: String { rawValue }
    public var title: String { self == .automatic ? "Auto · 512/1200/2400" : "\(rawValue.dropFirst(3)) baud" }
    public var demodulators: [String] {
        switch self { case .automatic: ["POCSAG512", "POCSAG1200", "POCSAG2400"]
        case .bps512: ["POCSAG512"]; case .bps1200: ["POCSAG1200"]; case .bps2400: ["POCSAG2400"] }
    }
}
public enum FiveToneStandard: String, CaseIterable, Codable, Sendable, Identifiable {
    case zvei1 = "ZVEI1", zvei2 = "ZVEI2", zvei3 = "ZVEI3", pzvei = "PZVEI", dzvei = "DZVEI", eea = "EEA", eia = "EIA", ccir = "CCIR"
    public var id: String { rawValue }
}
public enum RTTYEncoding: String, CaseIterable, Codable, Sendable, Identifiable {
    case ita2 = "ITA2 · 5 bits", ascii7 = "ASCII · 7 bits", ascii8 = "ASCII · 8 bits"
    public var id: String { rawValue }
    public var dataBits: Int { self == .ita2 ? 5 : self == .ascii7 ? 7 : 8 }
}
public enum HellVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case feld = "Feld Hell", slow14 = "Slow Hell · 14 baud", slowFldigi = "Slow Hell · fldigi /8", x5 = "Feld Hell X5", x9 = "Feld Hell X9"
    public var id: String { rawValue }
    public var columnRate: Double { switch self { case .feld: 17.5; case .slow14: 2; case .slowFldigi: 2.1875; case .x5: 87.5; case .x9: 157.5 } }
    public var pixelRate: Double { 14 * columnRate }
    public var bandwidthHz: Double { switch self { case .feld: 350; case .slow14: 40; case .slowFldigi: 44; case .x5: 1750; case .x9: 3150 } }
}

public enum DSCVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case mfHF = "mf-hf", vhf
    public var id: String { rawValue }
    public var title: String { self == .mfHF ? "MF/HF · 100 baud · 170 Hz" : "VHF · 1200 baud · 1300/2100 Hz" }
}
