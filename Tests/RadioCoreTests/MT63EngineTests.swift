import Foundation
import Testing
@testable import RadioCore

@Test(arguments: MT63Variant.allCases)
func mt63ReceivesAllBandwidthAndInterleaveVariants(_ variant: MT63Variant) throws {
    let fixture = try #require(Bundle.module.url(
        forResource: "mt63_\(variant.bandwidth)_\(variant.interleave)_8000_clean",
        withExtension: "wav", subdirectory: "Fixtures"))
    var settings = DecoderSettings()
    settings.mt63Variant = variant
    settings.frequency = 1500
    let reader = try AudioFileReader(url: fixture)
    let process = try ExternalAudioEngine(mode: .mt63, settings: settings)
    defer { process.cancel() }
    while let samples = try reader.next() { try process.write(samples) }
    let result = try process.finish()
    #expect(result.text == "CQ TEST MT63 123")
    let decoded = try #require(result.records.first { !$0.text.isEmpty })
    #expect(decoded.locked == true)
    #expect(decoded.confidence.map { (0...1).contains($0) } == true)
    #expect(decoded.crcValid == nil && decoded.snrDB == nil)
    #expect(abs((decoded.frequencyHz ?? 0) - 1500) < 20)
}

@Test func mt63SilenceDoesNotInventText() throws {
    var settings = DecoderSettings()
    settings.frequency = 1500
    let process = try ExternalAudioEngine(mode: .mt63, settings: settings)
    defer { process.cancel() }
    for _ in 0..<120 { try process.write([Float](repeating: 0, count: 2000)) }
    let result = try process.finish()
    #expect(result.text.isEmpty)
    #expect(result.records.allSatisfy { $0.text.isEmpty && $0.locked != true })
}
