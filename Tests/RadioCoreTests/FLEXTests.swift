import Foundation
import Testing
import AVFoundation
@testable import RadioCore
@testable import RadioWorkbench

// Independent synthetic framing: generic polynomial division, no helper encoder,
// lookup table or correction routine. See script/validation/flex_fixture.py (MIT).
private func flexReverse(_ value: UInt32, bits: Int) -> UInt32 {
    (0..<bits).reduce(0) { ($0 << 1) | ((value >> $1) & 1) }
}
private func flexCodeword(_ data: UInt32) -> UInt32 {
    var remainder = flexReverse(data & 0x1fffff, bits: 21) << 10
    for bit in stride(from: 30, through: 10, by: -1) {
        if remainder & (1 << bit) != 0 { remainder ^= 0x769 << (bit - 10) }
    }
    let word = (data & 0x1fffff) | (flexReverse(remainder & 1023, bits: 10) << 21)
    return word | (UInt32(word.nonzeroBitCount & 1) << 31)
}
private func flexCheck(_ value: UInt32) -> UInt32 {
    (15 &- stride(from: 4, through: 20, by: 4).reduce(UInt32(0)) { $0 + ((value >> $1) & 15) }) & 15
}
private struct FlexVariant: Sendable, CustomTestStringConvertible {
    let baud: Int, levels: Int
    var testDescription: String { "\(baud) Bd/\(levels)-FSK" }
    var phases: [String] { baud == 1600 ? (levels == 2 ? ["A"] : ["A", "B"]) : (levels == 2 ? ["A", "C"] : ["A", "B", "C", "D"]) }
    var sync: UInt64 { baud == 1600 ? (levels == 2 ? 0x870c : 0xb068) : (levels == 2 ? 0x7b18 : 0xdea0) }
}
private let flexVariants = [FlexVariant(baud: 1600, levels: 2), FlexVariant(baud: 1600, levels: 4), FlexVariant(baud: 3200, levels: 2), FlexVariant(baud: 3200, levels: 4)]
private let flexMessage = "CQ RADIOWORKBENCH FLEX TEST"
private func flexAudio(variant: FlexVariant, inverted: Bool = false, damage: Int = 0, capcode: UInt32 = 1_234_567, rate: Int = 22_050, fragment: Int = 3) -> [Float] {
    var data = (0..<88).map { UInt32($0.isMultiple(of: 2) ? 0xaaaaa : 0x155555) }
    var slots = [UInt32(0)] + flexMessage.utf8.map(UInt32.init) + [3]
    while slots.count % 3 != 0 { slots.append(3) }
    slots[0] = ~slots.dropFirst().filter { $0 != 3 }.reduce(0, +) & 127
    var payload: [UInt32] = []
    for i in stride(from: 0, to: slots.count, by: 3) { payload.append(slots[i] | (slots[i + 1] << 7) | (slots[i + 2] << 14)) }
    var header = UInt32(fragment << 11) | (1 << 19)
    let sum = ([header] + payload).reduce(UInt32(0)) { $0 + ($1 & 255) + (($1 >> 8) & 255) + (($1 >> 16) & 31) }
    header |= ~sum & 1023
    payload.insert(header, at: 0)
    data[0] = 2 << 10; data[1] = capcode + 0x8000
    let vector = UInt32(5 << 4) | (3 << 7) | (UInt32(payload.count) << 14)
    data[2] = vector | flexCheck(vector)
    data.replaceSubrange(3..<(3 + payload.count), with: payload)
    var words = data.map(flexCodeword)
    if damage > 0 { for bit in [2, 11, 23].prefix(damage) { words[1] ^= 1 << bit } }
    let sync = (variant.sync << 48) | (0xa6c6aaaa << 16) | (variant.sync ^ 65535)
    var bits = (0..<960).map { UInt32($0 & 1) }
    bits += stride(from: 63, through: 0, by: -1).map { 1 - UInt32((sync >> $0) & 1) }
    bits += (0..<16).map { UInt32($0 & 1) }
    let fiw = UInt32(2 << 4) | (42 << 8)
    let encodedFIW = flexCodeword(fiw | flexCheck(fiw))
    bits += (0..<32).map { (encodedFIW >> $0) & 1 }
    var first: [Float] = []
    for bit in bits { first.append(bit == 1 ? Float(0.6) : Float(-0.6)) }
    var sync2: [UInt32] = []
    for index: Int in 0..<4 { sync2.append(UInt32(index & 1)) }
    for bit: Int in stride(from: 15, through: 0, by: -1) { sync2.append((UInt32(0xed84) >> bit) & 1) }
    for index: Int in 0..<4 { sync2.append(UInt32(1 - (index & 1))) }
    for bit: Int in stride(from: 15, through: 0, by: -1) { sync2.append((UInt32(0x127b) >> bit) & 1) }
    var second: [Float] = []
    for _: Int in 0..<(variant.baud / 1600) {
        for bit in sync2 { second.append(bit == 1 ? Float(0.6) : Float(-0.6)) }
    }
    for block in 0..<11 {
        for bit in 0..<32 {
            for index in (block * 8)..<(block * 8 + 8) {
                let value: Float = (words[index] >> bit) & 1 == 1 ? (variant.levels == 4 ? 0.2 : 0.6) : -0.6
                second += Array(repeating: value, count: variant.baud / 1600)
            }
        }
    }
    for index: Int in 0..<128 { second.append((index & 1) == 1 ? Float(0.6) : Float(-0.6)) }
    var result: [Float] = []
    let segments: [([Float], Int)] = [(first, 1600), (second, variant.baud)]
    for (symbols, baud) in segments {
        let count = Int(ceil(Double(symbols.count * rate) / Double(baud)))
        for sampleIndex: Int in 0..<count {
            let symbolIndex = min(symbols.count - 1, sampleIndex * baud / rate)
            result.append(symbols[symbolIndex])
        }
    }
    result += [Float](repeating: 0, count: rate * 2)
    return inverted ? result.map { -$0 } : result
}
private func flexResult(_ samples: [Float]) throws -> MultimonSnapshot {
    let helper = try MultimonProcess(mode: .flex, settings: DecoderSettings())
    defer { helper.cancel() }
    for offset in stride(from: 0, to: samples.count, by: 997) { try helper.write(Array(samples[offset..<min(samples.count, offset + 997)])) }
    return try helper.finish()
}

@Test(arguments: flexVariants, [false, true])
private func flexVariantsDecodeExactShortAddressAndPhaseAfterSilence(_ variant: FlexVariant, inverted: Bool) throws {
    for damage in 0...2 {
        let result = try flexResult(flexAudio(variant: variant, inverted: inverted, damage: damage))
        #expect(result.invalidLines == 0)
        #expect(result.records.count == variant.phases.count)
        #expect(result.records.map { $0.flex?.phase } == variant.phases.map(Optional.some))
        #expect(result.records.allSatisfy { $0.address == 1_234_567 && $0.kind == "ALPHA" && $0.body == flexMessage })
        #expect(result.records.allSatisfy { $0.flex?.symbolRate == variant.baud && $0.flex?.levels == variant.levels && $0.flex?.cycle == 2 && $0.flex?.frame == 42 && $0.flex?.fragment == "K" })
        let exported = try JSONDecoder().decode([MultimonRecord].self, from: JSONEncoder().encode(result.records))
        #expect(exported.map(\.flex) == result.records.map(\.flex))
    }
}

@Test(arguments: flexVariants)
private func flexRejectsThreeDamagedAddressBitsAndReacquires(_ variant: FlexVariant) throws {
    let corrupted = flexAudio(variant: variant, damage: 3)
    #expect(try flexResult(corrupted).records.isEmpty)
    let recovered = try flexResult(corrupted + flexAudio(variant: variant))
    #expect(recovered.records.map(\.address) == variant.phases.map { _ in 1_234_567 })
}

@Test private func flexSilenceNoiseAndUnsupportedLongAddressesCannotBecomeReceipts() throws {
    #expect(try flexResult([Float](repeating: 0, count: 44_100)).records.isEmpty)
    var seed: UInt64 = 42
    let noise: [Float] = (0..<44_100).map { _ in seed = seed &* 6_364_136_223_846_793_005 &+ 1; return Float(Int64(bitPattern: seed)) / Float(Int64.max) * 0.4 }
    #expect(try flexResult(noise).records.isEmpty)
    #expect(try flexResult(flexAudio(variant: flexVariants[0], capcode: 2_000_000)).records.isEmpty)
}

@Test private func flexPartialAlphaIsLabelledAsFragment() throws {
    let result = try flexResult(flexAudio(variant: flexVariants[0], fragment: 2))
    #expect(result.records.first?.kind == "ALPHA · fragmento C")
    #expect(result.records.first?.flex?.fragment == "C")
}

@Test(arguments: ["alpha", "numeric"])
private func flexFixtureReachesMonitorBeforeEOF(_ kind: String) async throws {
    let url = try #require(Bundle.module.url(forResource: "flex_22050_mono_\(kind)", withExtension: "wav", subdirectory: "Fixtures"))
    let file = try AVAudioFile(forReading: url)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    let helper = try MultimonProcess(mode: .flex, settings: DecoderSettings())
    defer { helper.cancel() }
    try helper.write(samples)
    let deadline = Date().addingTimeInterval(3)
    while helper.snapshot.records.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(helper.isRunning)
    #expect(helper.snapshot.records.first?.address == 1_234_567)
    #expect(helper.snapshot.records.first?.body == (kind == "alpha" ? flexMessage : "1234567890"))
    helper.cancel()
    #expect(helper.snapshot.records.count == 1)
}

@Test private func flexSchemaRejectsMalformedFieldsWithoutCoercingNumbers() throws {
    let valid: [String: Any] = ["demod_name": "flex_alphanumeric", "sync_baud": 1600, "sync_level": 2, "phase_number": "A", "cycle_number": 2, "frame_number": 42, "capcode": 1234567, "fragment_flag": "K", "message": flexMessage]
    func parse(_ row: [String: Any]) throws -> MultimonRecord? { MultimonRecord.parse(try JSONSerialization.data(withJSONObject: row), mode: .flex, standard: .zvei1) }
    #expect(try parse(valid) != nil)
    for key in valid.keys { var row = valid; row.removeValue(forKey: key); #expect(try parse(row) == nil) }
    let invalidFields: [(String, Any)] = [("sync_baud", 6400), ("sync_level", 3), ("phase_number", "B"), ("cycle_number", 15), ("frame_number", 128), ("capcode", -1), ("capcode", 1.25), ("capcode", "1234567"), ("capcode", true), ("capcode", 4_297_068_542 as Int64), ("fragment_flag", "?"), ("message", String(repeating: "x", count: 1025)), ("message", "bad\u{00}message"), ("demod_name", "flex_unknown")]
    for (key, value) in invalidFields {
        var row = valid; row[key] = value; #expect(try parse(row) == nil)
    }
}
