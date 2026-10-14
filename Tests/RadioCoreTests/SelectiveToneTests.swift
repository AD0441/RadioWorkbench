import Foundation
import Testing
@testable import RadioCore

// Independent mathematical audio synthesis. No detector table is read by the
// generator; selected test frequencies are literal protocol values.
private func selectiveAudio(_ rate: Double, seconds: Double, frequency: Double?, amplitude: Double = 0.24,
                            voice: Bool = false, noise: Bool = false) -> [Float] {
    var random: UInt32 = 0x672541
    return (0..<Int(rate * seconds)).map { sample in
        let t = Double(sample) / rate
        var value = frequency.map { amplitude * sin(2 * .pi * $0 * t + 0.731) } ?? 0
        if voice {
            value += 0.26 * sin(2 * .pi * 510 * t) + 0.15 * sin(2 * .pi * 1150 * t + 1.2)
            value += 0.12 * sin(2 * .pi * 1790 * t + 2.1)
        }
        if noise {
            random = random &* 1664525 &+ 1013904223
            value += (Double(random >> 8) / 16777216 - 0.5) * 0.25
        }
        return Float(value)
    }
}

private func selectiveDecoder(rate: Double, threshold: Double = 0.08) -> SelectiveToneDecoder {
    var settings = DecoderSettings(); settings.threshold = threshold
    return SelectiveToneDecoder(sampleRate: rate, settings: settings)
}

private func selectiveProcess(_ decoder: SelectiveToneDecoder, _ samples: [Float]) {
    for start in stride(from: 0, to: samples.count, by: 317) {
        decoder.process(Array(samples[start..<min(start + 317, samples.count)]))
    }
}

@Test(arguments: [
    67.0,69.3,71.9,74.4,77.0,79.7,82.5,85.4,88.5,91.5,
    94.8,97.4,100.0,103.5,107.2,110.9,114.8,118.8,123.0,127.3,
    131.8,136.5,141.3,146.2,150.0,151.4,156.7,159.8,162.2,165.5,
    167.9,171.3,173.8,177.3,179.9,183.5,186.2,189.9,192.8,196.6,
    199.5,203.5,206.5,210.7,218.1,225.7,229.1,233.6,241.8,250.3,254.1
])
func selectiveNeighborAndBoundaryTones(_ frequency: Double) {
    let decoder = selectiveDecoder(rate: 8000)
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 4, frequency: frequency))
    #expect(decoder.frequency == frequency)
    #expect(decoder.detections == 1)
    #expect(decoder.confidence >= 0.90)
    #expect(decoder.confirmedDuration >= 1)
}

@Test(arguments: [44100.0,48000.0])
func selectiveFractionalResamplingWithVoiceAndNoise(_ rate: Double) {
    let decoder = selectiveDecoder(rate: rate)
    selectiveProcess(decoder, selectiveAudio(rate, seconds: 4, frequency: 88.5, voice: true, noise: true))
    #expect(decoder.frequency == 88.5)
    #expect(decoder.detections == 1)
    #expect(decoder.confidence > 0.75)
}

@Test(arguments: ["silence","voice","voice_model","noise","off_table","alias","midpoint","weak","brief","two_tones","changing_pitch"])
func selectiveRejectsUnqualifiedAudio(_ variant: String) {
    let rate = 8000.0
    let decoder = selectiveDecoder(rate: rate)
    var samples: [Float]
    switch variant {
    case "silence": samples = selectiveAudio(rate, seconds: 4, frequency: nil)
    case "voice": samples = selectiveAudio(rate, seconds: 4, frequency: nil, voice: true)
    case "noise": samples = selectiveAudio(rate, seconds: 4, frequency: nil, noise: true)
    case "off_table": samples = selectiveAudio(rate, seconds: 4, frequency: 130)
    case "alias": samples = selectiveAudio(rate, seconds: 4, frequency: 770, amplitude: 0.8)
    case "midpoint": samples = selectiveAudio(rate, seconds: 4, frequency: 150.7)
    case "weak": samples = selectiveAudio(rate, seconds: 4, frequency: 100, amplitude: 0.02)
    case "brief":
        samples = selectiveAudio(rate, seconds: 0.35, frequency: 100)
        samples += selectiveAudio(rate, seconds: 3.65, frequency: nil)
    case "two_tones":
        samples = selectiveAudio(rate, seconds: 4, frequency: 67)
        let second = selectiveAudio(rate, seconds: 4, frequency: 69.3)
        for index in samples.indices { samples[index] += second[index] }
    case "voice_model":
        samples = (0..<32000).map { index in
            let t = Double(index) / rate
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 4 * t)
            let phase = 2 * .pi * (125 * t + 2 * sin(2 * .pi * 1.7 * t))
            return Float(envelope * (0.3 * sin(phase) + 0.15 * sin(2 * phase) + 0.08 * sin(4 * phase)))
        }
    default:
        samples = (0..<32000).map { index in
            let t = Double(index) / rate
            return Float(0.24 * sin(2 * .pi * (100 * t + 4 * t * t)))
        }
    }
    selectiveProcess(decoder, samples)
    #expect(decoder.frequency == nil)
    #expect(decoder.detections == 0)
    #expect(decoder.text.isEmpty)
}

@Test func selectiveToneReleaseAndChangeAreHysteretic() {
    let decoder = selectiveDecoder(rate: 8000)
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 4, frequency: 150))
    #expect(decoder.frequency == 150)
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 3, frequency: nil))
    #expect(decoder.frequency == nil)
    #expect(decoder.text.contains("fin confirmado"))
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 4, frequency: 151.4))
    #expect(decoder.frequency == 151.4)
    #expect(decoder.detections == 2)
}

@Test func selectiveWeakToneCanUseTheExplicitThreshold() {
    let decoder = selectiveDecoder(rate: 8000, threshold: 0.02)
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 4, frequency: 123, amplitude: 0.04))
    #expect(decoder.frequency == 123)
}

@Test func selectiveToneCanChangeWithoutSilence() {
    let decoder = selectiveDecoder(rate: 8000)
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 4, frequency: 150))
    #expect(decoder.frequency == 150)
    selectiveProcess(decoder, selectiveAudio(8000, seconds: 4, frequency: 151.4))
    #expect(decoder.frequency == 151.4)
    #expect(decoder.detections == 2)
    #expect(decoder.text.contains("CTCSS 150.0 Hz · fin confirmado"))
}

@Test func selectiveEngineIntegrationDecodesTheBundledDemo() throws {
    let url = try #require(Bundle.module.url(forResource: "ctcss_8000_mono_100hz", withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url)
    var settings = DecoderSettings(); settings.threshold = 0.02
    let engine = try DecoderEngine(mode: .selectiveTones, sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() { engine.process(samples) }
    engine.finish()
    #expect(engine.text.contains("CTCSS 100.0 Hz · inicio confirmado"))
    #expect(engine.text.contains("CTCSS 100.0 Hz · fin confirmado"))
    #expect(engine.status.contains("1 detecciones confirmadas"))
}
