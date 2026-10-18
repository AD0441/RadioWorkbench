import Foundation

public struct PacketReception: Sendable, Identifiable {
    public let id: UUID
    public let receivedAt: Date
    public let monitorLine: String
    public let position: RadioPosition?
}
struct PacketAX25Address: Equatable, Sendable {
    let callsign: String
    let ssid: UInt8
    let repeated: Bool
    var label: String { callsign + (ssid == 0 ? "" : "-\(ssid)") }
}

// UI frames only. This is a passive monitor, not a connected-mode AX.25 TNC.
struct PacketAX25Frame: Equatable, Sendable {
    let destination: PacketAX25Address
    let source: PacketAX25Address
    let path: [PacketAX25Address]
    let control: UInt8
    let protocolID: UInt8
    let information: [UInt8]

    static func parse(_ bytes: [UInt8]) -> PacketAX25Frame? {
        guard (16...328).contains(bytes.count) else { return nil }
        var addresses: [PacketAX25Address] = []
        addresses.reserveCapacity(10)
        var offset = 0
        while addresses.count < 10 {
            guard offset + 7 <= bytes.count else { return nil }
            var name: [UInt8] = []
            var padding = false
            for byte in bytes[offset..<(offset + 6)] {
                guard byte & 1 == 0 else { return nil }
                let character = byte >> 1
                if character == 32 { padding = true; continue }
                guard !padding, (48...57).contains(character) || (65...90).contains(character) else { return nil }
                name.append(character)
            }
            guard !name.isEmpty else { return nil }
            let flags = bytes[offset + 6]
            addresses.append(PacketAX25Address(callsign: String(decoding: name, as: UTF8.self),
                                               ssid: (flags >> 1) & 15, repeated: flags & 128 != 0))
            offset += 7
            if flags & 1 != 0 { break }
        }
        guard addresses.count >= 2, bytes[offset - 1] & 1 != 0, offset + 2 <= bytes.count else { return nil }
        let control = bytes[offset], protocolID = bytes[offset + 1]
        guard control & 0xEF == 0x03 else { return nil }
        let information = Array(bytes[(offset + 2)...])
        guard information.count <= 256 else { return nil }
        return PacketAX25Frame(destination: addresses[0], source: addresses[1], path: Array(addresses.dropFirst(2)),
                               control: control, protocolID: protocolID, information: information)
    }

    // Preserve non-ASCII and control octets visibly instead of interpreting
    // terminal escapes or inventing APRS field values.
    var monitorLine: String {
        let route = path.map { $0.label + ($0.repeated ? "*" : "") }
        let header = source.label + ">" + destination.label + (route.isEmpty ? "" : "," + route.joined(separator: ","))
        let payload = information.map { byte in
            if (32...126).contains(byte) { return String(UnicodeScalar(byte)) }
            return String(format: "\\x%02X", byte)
        }.joined()
        return header + (protocolID == 0xF0 ? ":" : String(format: " [PID %02X]:", protocolID)) + payload
    }
}

enum PacketFCS {
    // Reflected CRC-16/IBM-SDLC (X-25 FCS), init FFFF, polynomial 8408.
    // With the complemented FCS included, a valid frame leaves residue F0B8.
    static func residue(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0xFFFF
        for byte in bytes {
            value ^= UInt16(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 != 0 ? 0x8408 : 0) }
        }
        return value
    }
}

final class PacketHDLCReceiver {
    private var history: UInt8 = 0
    private var inFrame = false
    private var rawBits: [Bool] = []
    private(set) var frames: [PacketAX25Frame] = []
    private(set) var receptions: [PacketReception] = []
    private(set) var text = ""
    private(set) var accepted = 0, rejectedCRC = 0, rejectedFormat = 0, aborted = 0

    init() { rawBits.reserveCapacity(4096) }

    func loseSignal() {
        history = 0; inFrame = false
        rawBits.removeAll(keepingCapacity: true)
    }

    // Input is data after NRZI. Delimiters are detected before bit unstuffing.
    func push(bit: Bool) {
        history = (history >> 1) | (bit ? 128 : 0)
        if inFrame { rawBits.append(bit) }
        if history == 0x7E {
            if inFrame, rawBits.count > 8 {
                rawBits.removeLast(8)
                acceptFrame()
            }
            rawBits.removeAll(keepingCapacity: true)
            inFrame = true
        } else if history & 0xFE == 0xFE {
            if inFrame, !rawBits.isEmpty { aborted += 1 }
            inFrame = false
            rawBits.removeAll(keepingCapacity: true)
        } else if rawBits.count > 4096 {
            rejectedFormat += 1
            inFrame = false
            rawBits.removeAll(keepingCapacity: true)
        }
    }

    private func acceptFrame() {
        var ones = 0, bitCount = 0
        var byte: UInt8 = 0
        var bytes: [UInt8] = []
        bytes.reserveCapacity(330)
        for bit in rawBits {
            if !bit && ones == 5 { ones = 0; continue }
            ones = bit ? ones + 1 : 0
            guard ones < 6 else { rejectedFormat += 1; return }
            if bit { byte |= 1 << bitCount }
            bitCount += 1
            if bitCount == 8 {
                bytes.append(byte); byte = 0; bitCount = 0
                guard bytes.count <= 330 else { rejectedFormat += 1; return }
            }
        }
        guard bitCount == 0, bytes.count >= 18 else { rejectedFormat += 1; return }
        guard PacketFCS.residue(bytes) == 0xF0B8 else { rejectedCRC += 1; return }
        bytes.removeLast(2)
        guard let frame = PacketAX25Frame.parse(bytes) else { rejectedFormat += 1; return }
        accepted += 1
        let now = Date()
        receptions.append(PacketReception(id: UUID(), receivedAt: now, monitorLine: frame.monitorLine,
            position: APRSPositionParser.parse(frame.monitorLine, receivedAt: now)))
        if receptions.count > 64 { receptions.removeFirst(receptions.count - 64) }
        frames.append(frame)
        if frames.count > 64 { frames.removeFirst(frames.count - 64) }
        text.append(frame.monitorLine + "\n")
        if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
    }

    var status: String {
        "AX.25 UI · \(accepted) CRC válidos · \(rejectedCRC) CRC rechazados · \(rejectedFormat) formato rechazado · \(aborted) abortados"
    }
}
