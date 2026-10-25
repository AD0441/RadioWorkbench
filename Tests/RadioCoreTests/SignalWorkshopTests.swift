import Foundation
import Testing
@testable import RadioCore

@Test(arguments: [SignalReference.cw, .rtty, .psk31]) func workshopReferencesShowKnownBandsAndPreserveLearningParameters(_ reference: SignalReference) throws {
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

@Test func workshopCatalogueUsesOnlyExistingRecordingsAndExplicitVariantSettings() throws {
    #expect(Set(SignalReference.allCases.map(\.id)).count == SignalReference.allCases.count)
    for reference in SignalReference.allCases {
        let url = try #require(Bundle.module.url(forResource: reference.fileName, withExtension: "wav", subdirectory: "Fixtures"))
        let reader = try AudioFileReader(url: url)
        try reference.settings.validated(sampleRate: reader.sampleRate, mode: reference.mode)
        #expect(!reference.expectedText.isEmpty && !reference.provenance.isEmpty)
    }
    let sstv = SignalReference.allCases.compactMap { reference -> SSTVFormat? in
        if case .sstv(let format) = reference { return format }; return nil
    }
    #expect(Set(sstv) == Set(SSTVFormat.allCases.filter { $0 != .automatic }))
    #expect(sstv.count == 41)
    #expect(SignalReference.hell(.x9).settings.frequency == 2000)
    #expect(SignalReference.dsc(.vhf).settings.dscVariant == .vhf)
    #expect(SignalReference.pocsag(.bps2400).settings.pagerRate == .bps2400)
}

@Test func workshopDoesNotSubstituteM17DataForDMRVoiceOrWrongSelcallStandard() {
    var settings = DecoderSettings()
    #expect(SignalReference.matching(mode: .digitalVoice, settings: settings) == nil)
    settings.digitalVoiceProtocol = .m17
    #expect(SignalReference.matching(mode: .digitalVoice, settings: settings) == .m17Data)
    #expect(SignalReference.m17Data.title.contains("sin voz"))
    settings.fiveToneStandard = .ccir
    #expect(SignalReference.matching(mode: .fiveTones, settings: settings) == nil)
    #expect(SignalReference.matching(mode: .dgps, settings: settings) == .dgps)
    #expect(SignalReference.matching(mode: .globeWireless, settings: settings) == nil)
    settings.sstvFormat = .martinM4
    #expect(SignalReference.matching(mode: .sstv, settings: settings) == .sstv(.martinM4))
}

@Test func workshopSpectrogramPreservesToneTimingAndFixedAudioScale() throws {
    let url = try #require(Bundle.module.url(forResource: "ctcss_8000_mono_100hz", withExtension: "wav", subdirectory: "Fixtures"))
    let result = try SignalProbe.analyze(url: url, frequencyLimit: 400)
    #expect(result.bins.count == SignalProbe.frequencyBins)
    #expect(result.waterfall.count == result.rowTimes.count)
    #expect(result.waterfall.count <= SignalProbe.maximumRows)
    #expect(result.upperFrequency <= 400 && result.upperFrequency > 390)
    #expect(result.rowTimes == result.rowTimes.sorted())
    #expect(result.waterfall.allSatisfy { $0.count == SignalProbe.frequencyBins && $0.allSatisfy(\.isFinite) })
    let silence = try #require(result.waterfall.first)
    #expect(silence.max() ?? 0 <= -90)
    let active = try #require(result.rowTimes.indices.first { result.rowTimes[$0] > 1 })
    let strongest = try #require(result.waterfall[active].indices.max { result.waterfall[active][$0] < result.waterfall[active][$1] })
    let frequency = Double(strongest) * result.upperFrequency / Double(result.bins.count)
    #expect(abs(frequency - 100) < 8)
    #expect(result.waterfall[active][strongest] > -20)
}

@Test func workshopSpectrogramBoundsWorkAndPreservesChosenChannel() throws {
    let longURL = try #require(Bundle.module.url(forResource: "noaa_apt_2400am_48000_mono_24lines", withExtension: "wav", subdirectory: "Fixtures"))
    let result = try SignalProbe.analyze(url: longURL, frequencyLimit: 6000)
    #expect(result.secondsAnalyzed == 12)
    #expect(result.waterfall.count <= 96 && result.bins.count == 256)
    #expect(result.upperFrequency == 6000)
    let stereoURL = try #require(Bundle.module.url(forResource: "navtex_48000_stereo_opposite", withExtension: "wav", subdirectory: "Fixtures"))
    let mixed = try SignalProbe.analyze(url: stereoURL)
    let left = try SignalProbe.analyze(url: stereoURL, channel: .channel(0))
    #expect(mixed.levelDB <= -90)
    #expect(left.levelDB > -20)
    #expect(left.channels == 2)
}

@Test func workshopAnalysisHonorsCancellation() async throws {
    let url = try #require(Bundle.module.url(forResource: "morse_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let work = Task.detached {
        withUnsafeCurrentTask { $0?.cancel() }
        return try SignalProbe.analyze(url: url)
    }
    do { _ = try await work.value; Issue.record("Cancelled analysis unexpectedly succeeded") }
    catch is CancellationError { }
}

@Test func receptionInspectorProfilesSeparateRFAndAudioAndRespectVariants() {
    var settings = DecoderSettings()
    settings.sstvFormat = .mp73N
    let hf = RadioMode.sstv.receptionProfile(settings: settings, variant: .hf)
    let vhf = RadioMode.sstv.receptionProfile(settings: settings, variant: .vhf)
    #expect(hf.modulation == .usb && vhf.modulation == .fm)
    #expect(hf.audioBand.contains("2044") && hf.rfBandwidth >= 2400)
    #expect(vhf.rfBandwidth == 12500)
    settings.dscVariant = .vhf
    #expect(RadioMode.gmdss.receptionProfile(settings: settings).modulation == .fm)
    settings.digitalVoiceProtocol = .nxdn48
    #expect(RadioMode.digitalVoice.receptionProfile(settings: settings).rfBandwidth == 6250)
    #expect(RadioMode.digitalVoice.receptionProfile(settings: settings).center == 0)
    settings.hellVariant = .x9; settings.frequency = 1500
    let hell = RadioMode.hell.receptionProfile(settings: settings)
    #expect(hell.center >= 2000 && hell.rfBandwidth >= 3700)
}

@Test(arguments: [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, .infinity, -.infinity, .nan])
func receptionInspectorSafelyPresentsUnvalidatedNumericEdits(_ value: Double) {
    var settings = DecoderSettings()
    settings.frequency = value; settings.shift = value
    for mode in [RadioMode.rtty, .bitAnalysis, .hell, .mt63] {
        let profile = mode.receptionProfile(settings: settings)
        #expect(profile.center.isFinite && profile.center > 0 && profile.center <= 192000)
        #expect(profile.rfBandwidth.isFinite && profile.rfBandwidth > 0)
        #expect(!profile.audioBand.isEmpty)
    }
}
