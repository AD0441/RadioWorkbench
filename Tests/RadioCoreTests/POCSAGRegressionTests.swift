import Foundation
import Testing
import AVFoundation
@testable import RadioCore
@testable import RadioWorkbench

// Independent over-the-air framing: sync + eight frames of two BCH(31,21)
// words, followed by even parity. No decoder tables or repair code are used.
private let pagerSync: UInt32 = 0x7cd215d8
private let pagerIdle: UInt32 = 0x7a89c197
private func pagerCodeword(_ data: UInt32) -> UInt32 {
    var remainder = data << 10
    for bit in stride(from: 30, through: 10, by: -1) {
        if remainder & (1 << bit) != 0 { remainder ^= 0x769 << (bit - 10) }
    }
    let value = (data << 10) | (remainder & 0x3ff)
    return (value << 1) | UInt32(value.nonzeroBitCount & 1)
}
private func pagerNoticeBatch(_ address: Int, function: UInt32 = 3) -> [UInt32] {
    var words = [UInt32](repeating: pagerIdle, count: 16)
    words[(address & 7) * 2] = pagerCodeword((UInt32(address >> 3) << 2) | function)
    return words
}
private func pagerBits(_ words: [UInt32], preamble: Bool = true) -> [UInt8] {
    var bits: [UInt8] = preamble ? (0..<576).map { UInt8($0 & 1) } : []
    for word in words {
        bits += stride(from: 31, through: 0, by: -1).map { UInt8((word >> $0) & 1) }
    }
    return bits
}
private func pagerAudio(_ bits: [UInt8], baud: Int, inverted: Bool, silence: Double, rate: Int = 22_050) -> [Float] {
    var samples = (0..<Int(ceil(Double(bits.count * rate) / Double(baud)))).map { index -> Float in
        let bit = bits[min(bits.count - 1, index * baud / rate)]
        return (bit == 1) != inverted ? 0.55 : -0.55
    }
    samples += [Float](repeating: 0, count: Int(silence * Double(rate)))
    return samples
}
private func pagerSettings(correction: Int = 2) -> DecoderSettings {
    var settings = DecoderSettings()
    settings.pagerShowEmpty = true
    settings.pagerCorrectionBits = correction
    return settings
}
private func pagerResult(_ samples: [Float], correction: Int = 2) throws -> MultimonSnapshot {
    let process = try MultimonProcess(mode: .pocsag, settings: pagerSettings(correction: correction))
    defer { process.cancel() }
    for offset in stride(from: 0, to: samples.count, by: 997) {
        try process.write(Array(samples[offset..<min(samples.count, offset + 997)]))
    }
    return try process.finish()
}

@Test(arguments: [512, 1200, 2400], [false, true])
func pocsagToneOnlyNoticeDoesNotInventAddressesAfterSilence(_ baud: Int, inverted: Bool) throws {
    // Every capcode frame, including frame seven next to the required sync.
    for frame in 0..<8 {
        let address = 123456 | frame
        let bits = pagerBits([pagerSync] + pagerNoticeBatch(address))
        let result = try pagerResult(pagerAudio(bits, baud: baud, inverted: inverted, silence: 2))
        #expect(result.records.map(\.address) == [address])
        #expect(result.records.allSatisfy { $0.function == 3 && $0.kind == "TONO" })
        let exported = try JSONDecoder().decode([MultimonRecord].self, from: JSONEncoder().encode(result.records))
        #expect(exported.map(\.address) == [address])
    }
}

@Test(arguments: [512, 1200, 2400])
func pocsagToneOnlyNoticeArrivesBeforeEOFAndSurvivesCancel(_ baud: Int) async throws {
    let address = 123461
    let process = try MultimonProcess(mode: .pocsag, settings: pagerSettings())
    defer { process.cancel() }
    // No EOF and no later text event: stdout must flush the notice itself.
    try process.write(pagerAudio(pagerBits([pagerSync] + pagerNoticeBatch(address)), baud: baud, inverted: false, silence: 0.2))
    let deadline = Date().addingTimeInterval(2)
    while process.snapshot.records.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(process.isRunning)
    #expect(process.snapshot.records.first?.address == address)
    process.cancel()
    #expect(process.snapshot.records.first?.address == address)
}

@Test(arguments: [512, 1200, 2400], [false, true])
func pocsagMissingPeriodicSyncDropsPayloadAndReacquiresFrameAlignment(_ baud: Int, inverted: Bool) throws {
    let first = 123459, untrusted = 654325, recovered = 765439
    // Zero and idle both pass BCH; neither is the mandatory batch sync.
    for missingSync in [UInt32(0), pagerIdle] {
        var bits = pagerBits([pagerSync] + pagerNoticeBatch(first) + [missingSync] + pagerNoticeBatch(untrusted))
        bits += [0, 1, 1, 0, 1] // reacquire at a different bit phase
        bits += pagerBits([pagerSync] + pagerNoticeBatch(recovered))
        let result = try pagerResult(pagerAudio(bits, baud: baud, inverted: inverted, silence: 1))
        #expect(result.records.map(\.address) == [first, recovered])
    }
}

@Test(arguments: [0, 1, 2], [false, true])
func pocsagTextCrossesBatchesWithCorrectablePeriodicSync(_ damagedBits: Int, inverted: Bool) throws {
    let message = "CQ RADIOWORKBENCH LONG MESSAGE ACROSS MULTIPLE POCSAG BATCHES " + String(repeating: "TEST ", count: 10)
    let payload = Array((message + "\u{03}").utf8).flatMap { byte in (0..<7).map { UInt32((byte >> $0) & 1) } }
    var words = [pagerCodeword((UInt32(123456 >> 3) << 2) | 3)]
    for start in stride(from: 0, to: payload.count, by: 20) {
        var value: UInt32 = 1 << 20
        for index in 0..<min(20, payload.count - start) { value |= payload[start + index] << (19 - index) }
        words.append(pagerCodeword(value))
    }
    var framed: [UInt32] = []
    for start in stride(from: 0, to: words.count, by: 16) {
        // Flips are in the sync information, not just its parity bit.
        let damage: UInt32 = damagedBits == 0 ? 0 : damagedBits == 1 ? 1 << 12 : (1 << 12) | (1 << 23)
        framed += [start == 0 ? pagerSync : pagerSync ^ damage]
        framed += words[start..<min(words.count, start + 16)]
        if words.count - start < 16 { framed += [UInt32](repeating: pagerIdle, count: 16 - (words.count - start)) }
    }
    framed += [pagerSync] + [UInt32](repeating: pagerIdle, count: 16)
    let result = try pagerResult(pagerAudio(pagerBits(framed), baud: 1200, inverted: inverted, silence: 1))
    #expect(result.records.contains { $0.address == 123456 && $0.kind == "ALPHA" && $0.body.hasPrefix(message) })
    #expect(result.records.allSatisfy { $0.address == 123456 })
}

@Test(arguments: [0, 1])
func pocsagPeriodicSyncHonorsTheConfiguredBCHLimit(_ correction: Int) throws {
    let first = 123456, untrusted = 654322, recovered = 765436
    let damagedSync = pagerSync ^ (1 << 12) ^ (1 << 23)
    let bits = pagerBits([pagerSync] + pagerNoticeBatch(first) + [damagedSync] + pagerNoticeBatch(untrusted)
        + [pagerSync] + pagerNoticeBatch(recovered))
    let result = try pagerResult(pagerAudio(bits, baud: 1200, inverted: false, silence: 1), correction: correction)
    #expect(result.records.map(\.address) == [first, recovered])
}

@Test func pocsagSilenceAloneIsEmptyAndRealCapcodeZeroRemainsValid() throws {
    #expect(try pagerResult([Float](repeating: 0, count: 44_100)).records.isEmpty)
    let bits = pagerBits([pagerSync] + pagerNoticeBatch(0))
    #expect(try pagerResult(pagerAudio(bits, baud: 1200, inverted: false, silence: 2)).records.map(\.address) == [0])
}

private actor PagerMonitorUpdates {
    var records: [MultimonRecord] = []
    func receive(_ update: RadioUpdate) { records = update.multimonRecords }
}

@Test func pocsagToneOnlyNoticeReachesLiveAndWAVMonitorsAt48kHz() async throws {
    let address = 123456
    let audio = pagerAudio(pagerBits([pagerSync] + pagerNoticeBatch(address)), baud: 1200, inverted: false, silence: 0.2, rate: 48_000)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count)))
    buffer.frameLength = AVAudioFrameCount(audio.count)
    audio.withUnsafeBufferPointer { samples in buffer.floatChannelData![0].update(from: samples.baseAddress!, count: audio.count) }
    let ring = try AudioSampleRing(capacity: 131_072)
    ring.write(buffer)
    #expect(ring.dropped == 0)
    let live = PagerMonitorUpdates()
    let scheduledAt = ProcessInfo.processInfo.systemUptime
    let task = Task {
        print("POCSAG 48 kHz: worker scheduled after \(ProcessInfo.processInfo.systemUptime - scheduledAt) s")
        try await RadioWorker().decodeLive(ring: ring, sampleRate: 48_000, mode: .pocsag, settings: pagerSettings(), source: "Synthetic POCSAG regression") {
            await live.receive($0)
        }
    }
    defer { task.cancel() }
    // The full DSP suite can saturate the cooperative executor before this
    // worker is scheduled. The contract is delivery with stdin still open.
    let deadline = Date().addingTimeInterval(10)
    while await live.records.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    let liveAddresses = await live.records.map(\.address)
    print("POCSAG 48 kHz: live addresses \(liveAddresses) after \(ProcessInfo.processInfo.systemUptime - scheduledAt) s, before cancellation")
    #expect(liveAddresses == [address])
    task.cancel()
    do { try await task.value } catch is CancellationError { }

    let file = FileManager.default.temporaryDirectory.appendingPathComponent("pocsag-notice-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: file) }
    do {
        let writer = try AVAudioFile(forWriting: file, settings: format.settings)
        try writer.write(from: buffer)
    }
    let wav = PagerMonitorUpdates()
    try await RadioWorker().decodeFile(url: file, mode: .pocsag, settings: pagerSettings()) { await wav.receive($0) }
    #expect(await wav.records.map(\.address) == [address])
}
