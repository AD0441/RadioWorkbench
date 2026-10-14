import Foundation
import Testing
@testable import RadioCore

@Test(arguments: [0, 1, 2, 3, 4])
func robot36CompatibilityIsExplicitAndScoped(_ scenario: Int) throws {
    var settings = DecoderSettings(); settings.frequency = 1900
    settings.sstvFormat = scenario == 2 ? .automatic : .robot36
    settings.sstvRobot36Compatibility = scenario != 0
    let decoder = try DecoderEngine(mode: .sstv, sampleRate: 8000, settings: settings)
    var phase = 0.0
    func tone(_ frequency: Double, _ seconds: Double) {
        let samples = (0..<Int((seconds * 8000).rounded())).map { _ -> Float in
            let sample = Float(0.6 * sin(phase)); phase += 2 * .pi * frequency / 8000; return sample
        }
        decoder.process(samples)
    }
    // Published classical VIS timing, but intentionally wrong even parity.
    // The explicit exception is limited to VIS 8 and a valid stop tone.
    let code = scenario == 3 ? 44 : 8
    tone(1900, 0.3); tone(1200, 0.01); tone(1900, 0.3); tone(1200, 0.03)
    for bit in 0..<7 { tone((code >> bit) & 1 == 1 ? 1100 : 1300, 0.03) }
    tone(1300, 0.03); tone(scenario == 4 ? 2300 : 1200, 0.03)
    tone(1200, 0.009); tone(1500, 0.003); tone(1900, 0.088); tone(1500, 0.006); tone(1900, 0.044)
    if [1, 2, 5].contains(scenario) {
        let image = try #require(decoder.image)
        #expect(image.width == 320); #expect(image.caption.contains("paridad no estándar"))
    } else { #expect(decoder.image == nil) }
}

@Test func robot36CCompatibilityWorksWithAutoVISAndOtherSelectedFormat() throws {
    var settings = DecoderSettings(); settings.frequency = 1900
    settings.sstvFormat = .martinM4; settings.imageAutoSync = true; settings.sstvRobot36Compatibility = true
    let decoder = try DecoderEngine(mode: .sstv, sampleRate: 8000, settings: settings)
    var phase = 0.0
    func tone(_ frequency: Double, _ seconds: Double) {
        let samples = (0..<Int((seconds * 8000).rounded())).map { _ -> Float in
            let sample = Float(0.6 * sin(phase)); phase += 2 * .pi * frequency / 8000; return sample
        }
        decoder.process(samples)
    }
    tone(1900, 0.3); tone(1200, 0.01); tone(1900, 0.3); tone(1200, 0.03)
    for bit in 0..<7 { tone((8 >> bit) & 1 == 1 ? 1100 : 1300, 0.03) }
    tone(1300, 0.03); tone(1200, 0.03)
    tone(1200, 0.009); tone(1500, 0.003); tone(1900, 0.088); tone(1500, 0.006); tone(1900, 0.044)
    let image = try #require(decoder.image)
    #expect(image.width == 320); #expect(image.caption.contains("paridad no estándar"))
}

// The independent published-timing WAV is presented with a mismatched sample
// clock. Both header timing and the 240 raster lines must use the correction.
@Test(arguments: [-18068.0, 25000])
func robot36ClockCorrectionPreservesRaster(_ ppm: Double) throws {
    let url = try #require(Bundle.module.url(forResource: "sstv_robot36_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url)
    let correction = 1 + ppm * 0.000001
    var settings = DecoderSettings(); settings.sstvFormat = .robot36
    settings.imageClockPPM = ppm; settings.frequency = 1900 * correction
    settings.sstvAutoCalibrate = false
    let rate = reader.sampleRate * correction
    let decoder = try DecoderEngine(mode: .sstv, sampleRate: rate, settings: settings)
    while let samples = try reader.next() { decoder.process(samples) }
    decoder.process([Float](repeating: 0, count: Int(rate * 0.05)))
    let image = try #require(decoder.image, "\(decoder.text)")
    #expect(image.width == 320); #expect(image.height == 240)
    #expect(image.caption.contains("imagen completa"))
    for row in [10, 120, 230] {
        // Top grayscale and bottom reversed bars run black-to-white;
        // the central color bars run white-to-black.
        let whiteColumn = row == 120 ? 20 : 300
        let blackColumn = row == 120 ? 300 : 20
        #expect(image.rgb[(row * 320 + whiteColumn) * 3] > 240)
        #expect(image.rgb[(row * 320 + blackColumn) * 3] < 15)
    }
}
