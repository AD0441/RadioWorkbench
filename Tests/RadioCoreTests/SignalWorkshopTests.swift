import Foundation
import Testing
@testable import RadioCore

@Test(arguments: SignalReference.allCases) func workshopReferencesShowKnownBandsAndPreserveLearningParameters(_ reference: SignalReference) throws {
    let url = try #require(Bundle.module.url(forResource: reference.fileName, withExtension: "wav", subdirectory: "Fixtures"))
    let result = try SignalProbe.analyze(url: url)
    #expect(result.sampleRate == 8000 && result.channels == 1 && result.secondsAnalyzed > 4 && result.secondsAnalyzed <= 12)
    let strongest = try #require(result.bins.indices.max(by: { result.bins[$0] < result.bins[$1] }))
    let frequency = Double(strongest) * result.upperFrequency / Double(result.bins.count)
    let targets = reference == .cw ? [700.0] : reference == .rtty ? [1415.0, 1585.0] : [1500.0]
    #expect(targets.contains { abs($0 - frequency) < 20 })
    let decoder = try DecoderEngine(mode: reference.mode, sampleRate: 8000, settings: reference.settings)
    let reader = try AudioFileReader(url: url)
    while let samples = try reader.next() { decoder.process(samples) }; decoder.finish()
    #expect(decoder.text.trimmingCharacters(in: .whitespacesAndNewlines) == reference.expectedText)
}
