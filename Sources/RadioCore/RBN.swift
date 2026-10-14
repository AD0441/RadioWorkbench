import Foundation

public enum RBNFeed: String, CaseIterable, Sendable, Identifiable {
    case cwRTTY = "CW + RTTY"
    case ft8 = "FT8"
    public var id: String { rawValue }
    public var port: UInt16 { self == .cwRTTY ? 7000 : 7001 }
}

public struct RBNSpot: Codable, Hashable, Sendable, Identifiable {
    public let spotter: String
    public let callsign: String
    public let frequencyKHz: Double
    public let mode: String
    public let snrDB: Int?
    public let speedWPM: Int?
    public let comment: String
    public let receivedAt: Date

    public var id: String {
        "\(spotter)|\(callsign)|\(frequencyKHz)|\(Int(receivedAt.timeIntervalSince1970))"
    }

    public var band: String? {
        let f = frequencyKHz
        return switch f {
        case 1_800..<2_000: "160 m"
        case 3_500..<4_000: "80 m"
        case 5_250..<5_450: "60 m"
        case 7_000..<7_300: "40 m"
        case 10_100..<10_150: "30 m"
        case 14_000..<14_350: "20 m"
        case 18_068..<18_168: "17 m"
        case 21_000..<21_450: "15 m"
        case 24_890..<24_990: "12 m"
        case 28_000..<29_700: "10 m"
        case 50_000..<54_000: "6 m"
        case 144_000..<148_000: "2 m"
        default: nil
        }
    }
}

public enum RBNParser {
    /// Parses the common DX-cluster line emitted by the RBN telnet relays.
    /// Examples: `DX de W3LPL-#: 14025.1 K1ABC CW 23 dB 30 WPM CQ`.
    public static func parse(_ line: String, receivedAt: Date = Date()) -> RBNSpot? {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 6, fields[0].uppercased() == "DX", fields[1].lowercased() == "de" else { return nil }
        let spotter = String(fields[2].dropLast(fields[2].hasSuffix(":") ? 1 : 0)).uppercased()
        guard validCallsign(spotter), let frequency = Double(fields[3]), frequency.isFinite,
              (1_800...450_000).contains(frequency), validCallsign(fields[4]) else { return nil }
        let mode = fields[5].uppercased()
        guard ["CW", "RTTY", "FT8", "FT4"].contains(mode) else { return nil }

        var snr: Int?
        var speed: Int?
        for index in fields.indices.dropFirst(6) {
            if fields[index].lowercased() == "db", index > 6 { snr = Int(fields[index - 1]) }
            if fields[index].uppercased() == "WPM", index > 6 { speed = Int(fields[index - 1]) }
        }
        let commentStart = fields.firstIndex(where: { ["CQ", "QRL", "BEACON"].contains($0.uppercased()) })
        let comment = commentStart.map { fields[$0...].joined(separator: " ") } ?? ""
        return RBNSpot(spotter: spotter, callsign: fields[4].uppercased(), frequencyKHz: frequency,
                       mode: mode, snrDB: snr, speedWPM: speed, comment: comment, receivedAt: receivedAt)
    }

    public static func validLogin(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty, trimmed.utf8.count <= 16,
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "/" || $0 == "-" }) else { return nil }
        return trimmed
    }

    private static func validCallsign(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20
            && value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "/" || $0 == "-" || $0 == "#" })
    }
}

/// Incremental telnet decoding: removes IAC negotiations and returns any
/// complete UTF-8 text lines plus the negative replies required by telnet.
public struct RBNTelnetDecoder: Sendable {
    private enum State: Sendable { case text, iac, negotiation(UInt8), subnegotiation, subnegotiationIAC }
    private var state: State = .text
    private var line: [UInt8] = []

    public init() {}

    public mutating func consume(_ data: Data) -> (lines: [String], replies: [UInt8]) {
        var lines: [String] = []
        var replies: [UInt8] = []
        for byte in data {
            switch state {
            case .text:
                if byte == 255 { state = .iac }
                else if byte == 10 || byte == 13 {
                    if !line.isEmpty {
                        lines.append(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                        line.removeAll(keepingCapacity: true)
                    }
                } else if line.count < 2_048 { line.append(byte) }
            case .iac:
                if (251...254).contains(byte) { state = .negotiation(byte) }
                else if byte == 250 { state = .subnegotiation }
                else { state = .text }
            case let .negotiation(command):
                if command == 251 { replies += [255, 254, byte] } // DONT
                if command == 253 { replies += [255, 252, byte] } // WONT
                state = .text
            case .subnegotiation:
                if byte == 255 { state = .subnegotiationIAC }
            case .subnegotiationIAC:
                state = byte == 240 ? .text : .subnegotiation
            }
        }
        return (lines, replies)
    }
}
