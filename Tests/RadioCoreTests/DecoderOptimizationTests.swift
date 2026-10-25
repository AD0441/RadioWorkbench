import Foundation
import Testing
@testable import RadioCore

/// Independent scalar FIR retained as a numerical oracle for the vectorized
/// path. This checks phase/delay, including ring wraps and changing frequencies.
private struct ScalarAnalyticReference {
    var history: [Double]
    let taps: [(Int, Double)]
    let delay: Int
    var cursor = 0
    init(rate: Double) {
        let length = min(257, max(63, Int(rate * 0.004) | 1))
        history = Array(repeating: 0, count: length); delay = (length - 1) / 2
        taps = (0..<length).compactMap { index in
            let offset = index - (length - 1) / 2
            guard offset != 0 && abs(offset) % 2 == 1 else { return nil }
            return (index, 2 * (0.54 - 0.46 * cos(2 * .pi * Double(index) / Double(length - 1))) / (.pi * Double(offset)))
        }
    }
    mutating func push(_ value: Float) -> (Double, Double) {
        history[cursor] = Double(value)
        let q = taps.reduce(0.0) { $0 + history[(cursor - $1.0 + history.count) % history.count] * $1.1 }
        let i = history[(cursor - delay + history.count) % history.count]
        cursor = (cursor + 1) % history.count
        return (i, q)
    }
}

@Test(arguments: [8000.0, 44100.0, 48000.0, 96000.0])
func analyticVectorizationPreservesPhaseAndCausalDelay(_ rate: Double) throws {
    var actual = AnalyticAudio(sampleRate: rate), reference = ScalarAnalyticReference(rate: rate)
    for index in 0..<6000 {
        let time = Double(index) / rate
        let sample = Float(0.5 * sin(2 * .pi * (1200 * time + 300 * time * time)) + 0.2 * cos(2 * .pi * 2300 * time))
        let expected = reference.push(sample)
        if let received = actual.push(sample) {
            #expect(abs(received.real - expected.0) < 1e-12)
            #expect(abs(received.imaginary - expected.1) < 1e-12)
            #expect(received.frequency.isFinite && received.amplitude.isFinite)
            #expect(abs(received.time - Double(index - (reference.history.count - 1) / 2) / rate) < 1e-12)
        }
    }
}

@Test func analyticInvalidSamplesDoNotPoisonFollowingReception() throws {
    var decoder = AnalyticAudio(sampleRate: 48000)
    for _ in 0..<512 { _ = decoder.push(0) }
    for value: Float in [.nan, .infinity, -.infinity] {
        let received = decoder.push(value)
        let result = try #require(received)
        #expect(result.frequency.isFinite && result.amplitude.isFinite)
    }
    var final = 0.0
    for index in 0..<4800 {
        let sample = Float(0.6 * sin(2 * .pi * 1700 * Double(index) / 48000))
        let received = decoder.push(sample)
        let result = try #require(received)
        #expect(result.frequency.isFinite && result.amplitude.isFinite)
        final = result.frequency
    }
    #expect(abs(final - 1700) < 10)
}

@Test(arguments: [RadioMode.pocsag, .flex, .fiveTones])
func discriminatorModesIgnoreUnusedAudioCenter(_ mode: RadioMode) throws {
    var settings = DecoderSettings(); settings.frequency = 5900
    try settings.validated(sampleRate: 8000, mode: mode)
    settings.frequency = .nan
    try settings.validated(sampleRate: 8000, mode: mode)
    #expect(throws: RadioError.self) { try settings.validated(sampleRate: 4000, mode: mode) }
}

@Test func recordingExportReplacesAtomicallyAndPreservesDestinationOnFailure() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-copy-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.wav"), output = folder.appendingPathComponent("output.wav")
    let old = Data("previous recording".utf8), new = Data((0..<1_048_576).map { UInt8($0 % 251) })
    try new.write(to: source); try old.write(to: output)
    #expect(throws: (any Error).self) { try AtomicFileCopy.copy(from: folder.appendingPathComponent("missing.wav"), to: output) }
    #expect(try Data(contentsOf: output) == old)
    try AtomicFileCopy.copy(from: source, to: output)
    #expect(try Data(contentsOf: output) == new)
    #expect(try Data(contentsOf: source) == new)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["output.wav", "source.wav"])
}
