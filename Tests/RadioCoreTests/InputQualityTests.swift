import Foundation
import Testing
@testable import RadioCore

@Test func inputQualityDistinguishesSilenceClippingAndInvalidSamples() {
    let analyzer = SpectrumAnalyzer()
    let quiet = analyzer.analyze([Float](repeating: 0, count: 2048), sampleRate: 48000)
    #expect(InputQualityAssessment.findings(frame: quiet, mode: .psk31, settings: .init(), dropped: 0, received: 2048).contains { $0.id == "quiet" })
    let clipped = analyzer.analyze([1, -1, 0.5, -.infinity, .nan], sampleRate: 48000)
    #expect(clipped.quality.clippedCount == 2)
    #expect(clipped.quality.invalidCount == 2)
    #expect(clipped.quality.clippedPercent == 40)
    let finiteBins = clipped.bins.allSatisfy { $0.isFinite }
    #expect(finiteBins)
    let findings = InputQualityAssessment.findings(frame: clipped, mode: .psk31, settings: .init(), dropped: 50, received: 100)
    #expect(findings.contains { $0.id == "drops" && $0.observation.contains("50.00") })
    #expect(findings.contains { $0.id == "clipping" })
}

@Test func inputQualityCleanToneDoesNotClaimCalibratedRadioSNR() {
    let samples: [Float] = (0..<4096).map { Float(0.3 * sin(2 * Double.pi * 1500 * Double($0) / 48000)) }
    let frame = SpectrumAnalyzer().analyze(samples, sampleRate: 48000)
    #expect(abs(frame.quality.dc) < 0.001)
    #expect(frame.quality.peak <= 0.301)
    #expect(InputQualityAssessment.findings(frame: frame, mode: .psk31, settings: .init(), dropped: 0, received: 4096).isEmpty)
}
