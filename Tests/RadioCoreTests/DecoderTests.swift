import Foundation
import Testing
@testable import RadioCore
import AudioRing

private let fixtures = ["morse", "rtty", "bpsk31", "dtmf"].flatMap { mode in
    ["8000_mono", "44100_stereo"].flatMap { layout in
        ["clean", "offset", "noisy"].map { "\(mode)_\(layout)_\($0)" }
    }
}

@Test(arguments: fixtures)
func independentAudioFixture(_ filename: String) throws {
    let url = try #require(Bundle.module.url(forResource: filename, withExtension: "wav", subdirectory: "Fixtures"))
    let mode: RadioMode = filename.hasPrefix("bpsk31") ? .psk31 : filename.hasPrefix("rtty") ? .rtty : filename.hasPrefix("dtmf") ? .dtmf : .morse
    let expected = mode == .psk31 ? "CQ test 123" : mode == .dtmf ? "123A456B789C*0#D" : "CQ TEST 123"
    let reader = try AudioFileReader(url: url)
    var settings = DecoderSettings(); settings.frequency = mode == .morse ? 700 : 1500
    let decoder = try DecoderEngine(mode: mode, sampleRate: reader.sampleRate, settings: settings)
    // Deliberately split at a boundary unrelated to any symbol or detector window.
    while let samples = try reader.next() {
        for start in stride(from: 0, to: samples.count, by: 317) {
            decoder.process(Array(samples[start..<min(start + 317, samples.count)]))
        }
    }
    decoder.finish()
    #expect(decoder.text.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
}

@Test func silenceAndSettings() throws {
    var settings = DecoderSettings()
    for mode in [RadioMode.morse, .rtty, .psk31, .dtmf, .navtex] {
        let decoder = try DecoderEngine(mode: mode, sampleRate: 8000, settings: settings)
        decoder.process([Float](repeating: 0, count: 16000)); decoder.finish()
        #expect(decoder.text.isEmpty)
    }
    settings.frequency = 5000
    #expect(throws: RadioError.self) { try DecoderEngine(mode: .morse, sampleRate: 8000, settings: settings) }
    #expect(throws: RadioError.self) { try DecoderEngine(mode: .ale, sampleRate: 48000, settings: settings) }
}

@Test func spectrumResolvesTone() {
    let sampleRate = 8000.0
    let samples = (0..<8192).map { Float(0.5 * sin(2 * .pi * 700 * Double($0) / sampleRate)) }
    let frame = SpectrumAnalyzer().analyze(samples, sampleRate: sampleRate)
    #expect(abs(frame.peakFrequency - 700) < 5)
    #expect(frame.levelDB > -10 && frame.levelDB < -8)
    #expect(!frame.clipped)
}

@Test func ringOverflowAndWrapPreserveOrder() throws {
    let ring = try #require(radio_ring_create(8)); defer { radio_ring_destroy(ring) }
    let initial: [Float] = [1, 2, 3, 4, 5, 6]
    let written = initial.withUnsafeBufferPointer { radio_ring_write_mono(ring, $0.baseAddress, nil, $0.count) }
    #expect(written == 6)
    var output = [Float](repeating: 0, count: 4)
    let count = output.withUnsafeMutableBufferPointer { radio_ring_read(ring, $0.baseAddress, $0.count) }
    #expect(count == 4); #expect(output == [1, 2, 3, 4])
    let more: [Float] = [7, 8, 9, 10, 11, 12]
    #expect(more.withUnsafeBufferPointer { radio_ring_write_mono(ring, $0.baseAddress, nil, $0.count) } == 6)
    #expect(initial.withUnsafeBufferPointer { radio_ring_write_mono(ring, $0.baseAddress, nil, $0.count) } == 0)
    #expect(radio_ring_dropped(ring) == 6)
    output = [Float](repeating: 0, count: 8)
    #expect(output.withUnsafeMutableBufferPointer { radio_ring_read(ring, $0.baseAddress, $0.count) } == 8)
    #expect(output == [5, 6, 7, 8, 9, 10, 11, 12])
}
