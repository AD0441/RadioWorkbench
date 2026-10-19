import Foundation

public enum DMRSlotSelection: String, Codable, CaseIterable, Identifiable, Sendable {
    case both, ts1, ts2
    public var id: String { rawValue }
    public var title: String { switch self { case .both: "Ambos · TS1 y TS2"; case .ts1: "TS1"; case .ts2: "TS2" } }
    /// DSD-neo -V is the synthesis mask. It is not the -z slot preference.
    public var synthesisMask: String { switch self { case .both: "3"; case .ts1: "1"; case .ts2: "2" } }
}

public struct DigitalVoicePCMChunk: Sendable {
    public let samples: [Float]
    public let channels: Int
    public var sampleRate: Double { 8000 }
    public var frameCount: Int { samples.count / channels }
}

/// DSD-neo 2.10.0 -fs stdout: signed 16-bit LE, 8 kHz, interleaved stereo.
/// Carries incomplete frames across pipe reads. Expects raw PCM, without WAV headers or text.
public struct DMRVoicePCMDecoder: Sendable {
    private var pending = Data()
    public private(set) var frames: UInt64 = 0
    public init() {}
    public mutating func consume(_ data: Data) -> [DigitalVoicePCMChunk] {
        pending.append(data)
        var chunks: [DigitalVoicePCMChunk] = []
        while pending.count >= 4 {
            let bytes = min(pending.count / 4, 2048) * 4
            let block = Array(pending.prefix(bytes))
            var samples = [Float](); samples.reserveCapacity(bytes / 2)
            for i in stride(from: 0, to: bytes, by: 2) {
                let value = Int16(bitPattern: UInt16(block[i]) | UInt16(block[i + 1]) << 8)
                samples.append(Float(value) / 32768)
            }
            pending.removeFirst(bytes)
            frames += UInt64(bytes / 4)
            chunks.append(DigitalVoicePCMChunk(samples: samples, channels: 2))
        }
        return chunks
    }
    public var incompleteBytes: Int { pending.count }
}

public struct DMRSlotStatus: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { slot }
    public let slot: Int
    public var colorCode: Int?
    public var sourceID: Int?
    public var targetID: Int?
    public var callKind: String?
    public var activity: String?
    public var updatedAt: Date?
    public var identityAt: Date?
    public init(slot: Int) { self.slot = slot }
}

public struct DMRStatus: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var engine = "DSD-neo 2.10.0"
    public var provenance = "Console adapter; timestamps are local processing times. CRC and transmitter identity are not independently verified."
    public var slots = [DMRSlotStatus(slot: 1), DMRSlotStatus(slot: 2)]
    public var lastSyncAt: Date?
    public var rejectedLines = 0
    public init() {}
}

/// Narrow adapter for the pinned engine's console, not a general DMR frame parser.
/// Missing fields stay unknown; error-marked LC lines never replace identities.
public struct DMRLogParser: Sendable {
    public private(set) var status = DMRStatus()
    private var pending = Data()
    private var colorCode: Int?
    private var contextAt: Date?
    public init() {}
    public mutating func consume(_ data: Data, at date: Date = Date()) {
        pending.append(data)
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let line = String(decoding: pending.prefix(upTo: end), as: UTF8.self)
            pending.removeSubrange(...end)
            consumeLine(line, at: date)
        }
        if pending.count > 16384 { pending.removeAll(keepingCapacity: true); contextAt = nil; colorCode = nil }
    }
    public mutating func finish(at date: Date = Date()) {
        if !pending.isEmpty { consumeLine(String(decoding: pending, as: UTF8.self), at: date); pending.removeAll() }
    }
    private mutating func consumeLine(_ raw: String, at date: Date) {
        let line = raw.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.contains("FEC ERR") || line.contains("CRC ERR") || line.contains("CACH/EMB ERR") || line.contains("CACH/SYNC ERR") {
            status.rejectedLines += 1
            contextAt = nil; colorCode = nil
            return
        }
        if line.contains("Sync: no sync") { contextAt = nil; colorCode = nil; return }
        if line.range(of: #"^(?:\d{2}:\d{2}:\d{2}\s+)?Sync:\s*[+-]?DMR\b"#, options: .regularExpression) != nil {
            status.lastSyncAt = date; contextAt = date
            colorCode = capture(#"Color Code=(\d{1,2})(?:\s|\|)"#, in: line).flatMap(Int.init).flatMap { (0...15).contains($0) ? $0 : nil }
            if let slot = capture(#"\[SLOT([12])\]"#, in: line).flatMap(Int.init) {
                status.slots[slot - 1].colorCode = colorCode
                status.slots[slot - 1].updatedAt = date
                status.slots[slot - 1].activity = line.contains("VC") ? "Voz" : "Ráfaga DMR"
            }
        } else if line.contains("Sync:") {
            contextAt = nil; colorCode = nil
        }
        guard let contextAt, date.timeIntervalSince(contextAt) >= 0, date.timeIntervalSince(contextAt) <= 2,
              let slot = capture(#"^SLOT ([12])\s+TGT="#, in: line).flatMap(Int.init),
              let target = capture(#"\bTGT=(\d{1,8})\b"#, in: line).flatMap(Int.init),
              let source = capture(#"\bSRC=(\d{1,8})\b"#, in: line).flatMap(Int.init),
              (1...16777215).contains(target), (1...16777215).contains(source) else { return }
        status.slots[slot - 1].colorCode = colorCode
        status.slots[slot - 1].sourceID = source; status.slots[slot - 1].targetID = target
        status.slots[slot - 1].callKind = line.contains("Private") ? "Individual" : line.contains("Group") ? "Grupo" : nil
        status.slots[slot - 1].activity = "Señalización de llamada"
        status.slots[slot - 1].updatedAt = date; status.slots[slot - 1].identityAt = date
    }
    private func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
