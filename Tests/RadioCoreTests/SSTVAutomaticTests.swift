import Foundation
import Testing
@testable import RadioCore

@Test(arguments: [-18068.0, 25000])
func sstvFindsClockWithoutManualPPM(_ sourcePPM: Double) throws {
    let url = try #require(Bundle.module.url(forResource: "sstv_robot36_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url)
    let rate = reader.sampleRate * (1 + sourcePPM * 1e-6)
    var settings = DecoderSettings(); settings.frequency = 1900; settings.sstvFormat = .robot36
    settings.imageClockPPM = 0; settings.sstvAutoCalibrate = true
    let decoder = try DecoderEngine(mode: .sstv, sampleRate: rate, settings: settings)
    while let samples = try reader.next() { decoder.process(samples) }
    decoder.process([Float](repeating: 0, count: Int(rate * 0.1)))
    let image = try #require(decoder.image, "\(decoder.text)")
    let calibration = try #require(decoder.sstvCalibration, "\(decoder.text)")
    #expect(image.width == 320); #expect(image.height == 240); #expect(image.caption.contains("imagen completa"))
    #expect(abs(calibration.clockPPM - sourcePPM) < 100)
    #expect(calibration.syncLines >= 64)
    for row in [10,120,230] {
        let white = row == 120 ? 20 : 300, black = row == 120 ? 300 : 20
        #expect(image.rgb[(row * 320 + white) * 3] > 240)
        #expect(image.rgb[(row * 320 + black) * 3] < 15)
    }
}

@Test func sstvClockRejectsRandomSyncAndRecoversMissingPulses() {
    var tracker = SSTVTimingTracker(period: 0.15, anchor: 1, correction: 1)
    for time in [1.002,1.035,1.091,1.16,1.211,1.246,1.499] { _ = tracker.observe(time) }
    #expect(tracker.fit == nil)
    tracker = SSTVTimingTracker(period: 0.15, anchor: 1, correction: 1)
    for line in 0..<80 where line % 11 != 5 { _ = tracker.observe(1 + Double(line) * 0.15276 + (line % 2 == 0 ? 0.0002 : -0.0002)) }
    let fit = tracker.fit
    #expect(fit != nil)
    if let fit { #expect(abs((0.15 / fit.period - 1) * 1e6 + 18068) < 100) }
}

@Test func sstvImpulseReductionPreservesThinLinesAndColorEdges() {
    let width = 9, height = 7
    var pixels = [UInt8](repeating: 100, count: width * height * 3)
    for row in 0..<height { for channel in 0..<3 { pixels[(row * width + 6) * 3 + channel] = 0 } }
    for channel in 0..<3 { pixels[(3 * width + 2) * 3 + channel] = 255 }
    let filtered = SSTVImageFilter.apply(pixels, width: width, height: height, reduction: .balanced)
    #expect(filtered[(3 * width + 2) * 3] == 100)
    #expect(filtered[(3 * width + 6) * 3] == 0)
    #expect(SSTVImageFilter.apply(pixels, width: width, height: height, reduction: .off) == pixels)
}

@Test(arguments: [
    ("sstv_martin_m1_8000_mono_clean", -18068.0),
    ("sstv_scottie_s1_8000_mono_clean", 25000.0),
    ("sstv_pd50_8000_mono_clean", -18068.0),
    ("sstv_mmsstv_mc110_n_8000_clean", 1000.0)
])
func sstvAutomaticTimingAcrossFamilies(_ sample: (String, Double)) throws {
    let url = try #require(Bundle.module.url(forResource: sample.0, withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url), rate = 8000 * (1 + sample.1 * 1e-6)
    var settings = DecoderSettings(); settings.frequency = 1900
    let decoder = try DecoderEngine(mode: .sstv, sampleRate: rate, settings: settings)
    while let samples = try reader.next() { decoder.process(samples) }
    decoder.process([Float](repeating: 0, count: Int(rate * 0.1)))
    let image = try #require(decoder.image, "\(decoder.text)")
    let calibration = decoder.sstvCalibration
    let status = decoder.text
    guard let fit = calibration else {
        Issue.record("No hay calibración SSTV: \(status)")
        return
    }
    #expect(image.width == 320); #expect(image.height == 256)
    // The narrow 8 kHz MC110-N fixture has coarser line-pulse timing than the
    // other families; its independent clock-stretch estimate is within 150 ppm.
    let tolerance = sample.0.contains("mc110_n") ? 150.0 : 100.0
    #expect(abs(fit.clockPPM - sample.1) < tolerance)
    #expect(image.rgb[(120 * 320 + 20) * 3] > 240)
    #expect(image.rgb[(120 * 320 + 300) * 3] < 15)
}
