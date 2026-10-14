import Foundation
import Testing
@testable import RadioCore

private func acarsAudio(_ name: String) throws -> AudioFileReader {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    return try AudioFileReader(url: url)
}
private func acarsDecode(_ name: String) throws -> ACARSProcessSnapshot {
    let reader = try acarsAudio(name), resampler = try ACARSAudioResampler(sampleRate: reader.sampleRate)
    let process = try ACARSProcess(); defer { process.cancel() }
    while let samples = try reader.next() {
        // Deliberately cross both symbol and source-rate boundaries.
        for start in stride(from: 0, to: samples.count, by: 317) {
            try process.write(resampler.process(Array(samples[start..<min(start+317,samples.count)])))
        }
    }
    try process.write(resampler.finish())
    return try process.finish()
}

@Test(arguments: ["acars_synthetic_12000","acars_synthetic_44100","acars_synthetic_48000"])
func acarsIndependentTransmission(_ name: String) throws {
    let result = try acarsDecode(name)
    #expect(result.total == 1); #expect(result.invalidLines == 0); #expect(result.queueDrops == 0)
    let message = try #require(result.messages.first)
    #expect(message.tail == "TEST00"); #expect(message.flight == "TST001")
    #expect(message.messageNumber == "0001"); #expect(message.body == "RADIOWORKBENCH ACARS TEST")
    #expect(message.label == "H1"); #expect(message.endBlock == 3); #expect(message.parityCorrections == 0)
}

@Test func acarsParityDamageIsRejected() throws {
    let result = try acarsDecode("acars_synthetic_bad_parity")
    #expect(result.total == 0); #expect(result.messages.isEmpty)
}
@Test func acarsRepairsSingleParityErrorAndRejectsInvalidCRC() throws {
    let repaired = try acarsDecode("acars_synthetic_repaired")
    #expect(repaired.total == 1)
    #expect(repaired.messages.first?.parityCorrections == 1)
    #expect(repaired.messages.first?.body == "RADIOWORKBENCH ACARS TEST")
    let rejected = try acarsDecode("acars_synthetic_bad_crc")
    #expect(rejected.total == 0)
}
@Test func acarsStopTerminatesItsOwnedHelper() async throws {
    let process = try ACARSProcess()
    #expect(process.isRunning)
    process.cancel()
    for _ in 0..<50 where process.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!process.isRunning)
}

@Test func acarsPublishedSampleAndFinalBlockAreRetained() throws {
    let result = try acarsDecode("acars_upstream_12000_mono")
    #expect(result.total == 1)
    let message = try #require(result.messages.first)
    #expect(message.tail == "F-GTAE"); #expect(message.flight == "AF7728")
    #expect(message.label == "H1"); #expect(message.body.hasPrefix("#DFB00000/V206"))
}

@Test func acarsSilenceAndRestartProduceNoFalseMessages() throws {
    for _ in 0..<3 {
        let process = try ACARSProcess()
        try process.write([Float](repeating: 0, count: 24000))
        let result = try process.finish()
        #expect(result.total == 0); #expect(result.invalidLines == 0)
    }
}

@Test func acarsPCMStreamContinuesAcrossMessages() throws {
    let reader = try acarsAudio("acars_synthetic_12000")
    var pcm: [Float] = []
    while let samples = try reader.next() { pcm.append(contentsOf: samples) }
    let process = try ACARSProcess()
    for _ in 0..<4 {
        for start in stride(from: 0, to: pcm.count, by: 257) { try process.write(Array(pcm[start..<min(start+257,pcm.count)])) }
    }
    let result = try process.finish()
    #expect(result.total == 4); #expect(result.messages.count == 4)
    #expect(result.messages.allSatisfy { $0.body == "RADIOWORKBENCH ACARS TEST" })
}

@Test func acarsResamplerPreservesDurationAndBlockContinuity() throws {
    let input = (0..<44100).map { Float(sin(2 * .pi * 2400 * Double($0) / 44100)) }
    let whole = try ACARSAudioResampler(sampleRate: 44100)
    let expected = whole.process(input) + whole.finish()
    let streaming = try ACARSAudioResampler(sampleRate: 44100)
    var actual: [Float] = []
    for start in stride(from: 0, to: input.count, by: 137) { actual += streaming.process(Array(input[start..<min(start+137,input.count)])) }
    actual += streaming.finish()
    #expect(actual.count == 12000)
    #expect(actual == expected)
    #expect(throws: RadioError.self) { try ACARSAudioResampler(sampleRate: 4000) }
}

@Test func acarsMissingMotorAndInvalidMessageAreExplicitErrors() {
    #expect(throws: RadioError.self) { try ACARSProcess(executableURL: URL(fileURLWithPath: "/tmp/does-not-exist-acars-helper")) }
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ACARSMessage.self, from: Data("{}".utf8)) }
}
@Test func acarsJSONExportRoundTripPreservesMessageFields() throws {
    let result = try acarsDecode("acars_synthetic_12000")
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result.messages)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("acars-export-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: path) }
    try data.write(to: path, options: .atomic)
    let decoded = try JSONDecoder().decode([ACARSMessage].self, from: Data(contentsOf: path))
    #expect(decoded.count == 1)
    #expect(decoded.first?.flight == "TST001")
    #expect(decoded.first?.ack == "\u{15}")
    #expect(decoded.first?.body == "RADIOWORKBENCH ACARS TEST")
}
