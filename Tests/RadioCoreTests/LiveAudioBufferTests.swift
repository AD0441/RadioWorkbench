import AVFoundation
import AudioRing
import Foundation
import Testing
@testable import RadioCore

@Test(arguments: [8000.0, 48000, 96000], [false, true])
func liveAudioChannels(sampleRate: Double, modern: Bool) throws {
    if modern, #unavailable(macOS 27) { return }
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)); buffer.frameLength = 4
    let planes = try #require(buffer.floatChannelData)
    let left: [Float] = [0.1, -0.2, 0.3, -0.4], right: [Float] = [-0.1, 0.4, -0.3, 0.8]
    for index in 0..<4 { planes[0][index] = left[index]; planes[1][index] = right[index] }
    for channel in [AudioChannelSelection.mix, .channel(0), .channel(1), .channel(2)] {
        let ring = try AudioSampleRing(channel: channel, capacity: 8)
        if modern, #available(macOS 27, *) { ring.write(AVReadOnlyAudioPCMBuffer(copying: buffer)) }
        else { ring.write(buffer) }
        var output = [Float](repeating: 0, count: 4)
        let count = ring.read(into: &output)
        if channel == .channel(2) { #expect(count == 0); #expect(ring.written == 0) }
        else {
            #expect(count == 4); #expect(ring.written == 4); #expect(ring.dropped == 0)
            for index in 0..<4 {
                let expected = channel == .mix ? (left[index] + right[index]) / 2 : channel == .channel(0) ? left[index] : right[index]
                #expect(abs(output[index] - expected) < 0.000001)
            }
        }
    }
}

@Test func liveAudioMonoAndOverflow() throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 96000, channels: 1, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)); buffer.frameLength = 4
    for index in 0..<4 { buffer.floatChannelData![0][index] = Float(index) / 8 }
    let ring = try AudioSampleRing(capacity: 4)
    ring.write(buffer); ring.write(buffer)
    #expect(ring.written == 4); #expect(ring.dropped == 4)
    var output = [Float](repeating: 0, count: 4)
    #expect(ring.read(into: &output) == 4); #expect(output == [0, 0.125, 0.25, 0.375])
    if #available(macOS 27, *) { ring.write(AVReadOnlyAudioPCMBuffer(copying: buffer)) }
    else { ring.write(buffer) }
    #expect(ring.written == 8); #expect(ring.read(into: &output) == 4)
    let interleaved = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true))
    let invalid = try #require(AVAudioPCMBuffer(pcmFormat: interleaved, frameCapacity: 4)); invalid.frameLength = 4
    ring.write(invalid); #expect(ring.written == 8)
}

// Low-level acoustic-like amplitude and the actual built-in input rate, through
// the same PCM/ring bridge used in Escuchar. Synthetic WAV, not an RF validation.
@Test(arguments: [false, true]) func liveAudioRobot36At96k(noisy: Bool) throws {
    let url = try #require(Bundle.module.url(forResource: "sstv_robot36_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let file = try AVAudioFile(forReading: url)
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 96000, channels: 1, interleaved: false))
    let converter = try #require(AVAudioConverter(from: file.processingFormat, to: format))
    let source = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
    let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048))
    let ring = try AudioSampleRing()
    var settings = DecoderSettings(); settings.frequency = 1900; settings.threshold = noisy ? 0.001 : 0.01
    let decoder = try DecoderEngine(mode: .sstv, sampleRate: 96000, settings: settings)
    var baselineSettings = settings; baselineSettings.sstvNoiseReduction = .off; baselineSettings.sstvAutoCalibrate = false
    let baseline = noisy ? try DecoderEngine(mode: .sstv, sampleRate: 96000, settings: baselineSettings) : nil
    var storage = [Float](repeating: 0, count: 2048)
    var readError: Error?
    var noiseState: UInt64 = 0x524F424F543336
    while true {
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            do {
                let remaining = file.length - file.framePosition
                guard remaining > 0 else { inputStatus.pointee = .endOfStream; return nil }
                try file.read(into: source, frameCount: AVAudioFrameCount(min(remaining, Int64(source.frameCapacity))))
                inputStatus.pointee = .haveData; return source
            } catch { readError = error; inputStatus.pointee = .endOfStream; return nil }
        }
        if let readError { throw readError }
        if let conversionError { throw conversionError }
        if status == .endOfStream { break }
        for index in 0..<Int(output.frameLength) {
            noiseState = noiseState &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float(Double(noiseState >> 11) / 9007199254740992 - 0.5) * 0.0002
            output.floatChannelData![0][index] = output.floatChannelData![0][index] * (noisy ? 0.005 : 0.04) + (noisy ? noise : 0)
        }
        if #available(macOS 27, *) { ring.write(AVReadOnlyAudioPCMBuffer(copying: output)) }
        else { ring.write(output) }
        let count = ring.read(into: &storage)
        if count > 0 { let samples = Array(storage.prefix(count)); decoder.process(samples); baseline?.process(samples) }
    }
    // A live input continues with ambient/silence after the final video tone.
    decoder.process([Float](repeating: 0, count: 4800))
    baseline?.process([Float](repeating: 0, count: 4800))
    decoder.finish()
    let image = try #require(decoder.image, "\(decoder.text)")
    #expect(image.width == 320); #expect(image.height == 240); #expect(image.caption.contains("imagen completa"))
    #expect(ring.dropped == 0); #expect(ring.written > 3_400_000)
    // Mid-image white and black bars must survive channel/rate conversion.
    let row = 120
    #expect(image.rgb[(row * 320 + 20) * 3] > (noisy ? 225 : 240))
    #expect(image.rgb[(row * 320 + 300) * 3] < (noisy ? 30 : 15))
    if let baseline {
        let original = try #require(baseline.image)
        let colors = [[255,255,255],[255,255,0],[0,255,255],[0,255,0],[255,0,255],[255,0,0],[0,0,255],[0,0,0]]
        var before = 0.0, after = 0.0
        for row in stride(from: 24, through: 216, by: 8) {
            for bar in 0..<8 { for channel in 0..<3 {
                let index = (row * 320 + bar * 40 + 20) * 3 + channel
                before += pow(Double(Int(original.rgb[index]) - colors[bar][channel]), 2)
                after += pow(Double(Int(image.rgb[index]) - colors[bar][channel]), 2)
            } }
        }
        #expect(after < before * 0.9, "Error cuadrático de color: sin reducción \(before), equilibrada \(after)")
        print("SSTV ruido 96 kHz · MSE de color: sin reducción \(before / 600), equilibrada \(after / 600)")
    }
}
