import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private actor DSCWorkerOutput {
    var latest: RadioUpdate?
    func ingest(_ value: RadioUpdate) { latest = value }
}
@Test(arguments: DSCVariant.allCases) func dscWorkerAcceptsOnlyCompleteECCFramesAndExportsSymbols(_ variant: DSCVariant) async throws {
    let name = variant == .vhf ? "dsc_vhf_48000_synthetic" : "dsc_mf_hf_48000_synthetic"
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    var settings = DecoderSettings(); settings.dscVariant = variant; settings.frequency = 1700
    let result = DSCWorkerOutput()
    try await RadioWorker().decodeFile(url: url, mode: .gmdss, settings: settings) { await result.ingest($0) }
    let value = try #require(await result.latest), record = try #require(value.engineRecords.first)
    #expect(value.finished && record.eccValid == true && record.interpretation == "partial")
    #expect(record.symbols?.isEmpty == false && record.dscVariant == variant.rawValue)
    if variant == .vhf { #expect(record.origin == "201444555" && record.destination == "233333334" && record.rxChannel == 8) }
    let decoded = try JSONDecoder().decode(AudioEngineRecord.self, from: JSONEncoder().encode(record))
    #expect(decoded.symbols == record.symbols && decoded.eccValid == true)
}
@Test func dscSettingsKeepOldProfilesAndRejectImpossibleAudioBand() throws {
    let old = try JSONDecoder().decode(DecoderSettings.self, from: Data("{}".utf8))
    #expect(old.dscVariant == .mfHF && !old.dscDeemphasized)
    var settings = old; settings.frequency = 3990
    #expect(throws: RadioError.self) { try settings.validated(sampleRate: 8000, mode: .gmdss) }
    #expect(RadioMode.gmdss.isAudioAvailable && RadioMode.gmdss.engineSampleRate == 48000)
}
