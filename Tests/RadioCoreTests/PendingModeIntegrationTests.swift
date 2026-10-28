import Foundation
import AVFoundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private actor PendingModeUpdates {
    var latest: RadioUpdate?
    func receive(_ update: RadioUpdate) { latest = update }
}

@Test @MainActor func mt63RFGuidePreservesShiftedAudioBand() throws {
    let receiver = ReceiverStore(); receiver.select(.mt63)
    receiver.settings.mt63Variant = .b2000Long; receiver.settings.frequency = 2500
    receiver.updateMT63Bandwidth()
    #expect(receiver.rfBandwidth > 3500)
    receiver.settings.frequency = 1000; receiver.applyMT63Variant()
    try receiver.settings.validated(sampleRate: 48000, mode: .mt63)
}

@Test @MainActor func switchingBackToDigitalVoicePreservesSelectedProtocolRFWidth() {
    let receiver = ReceiverStore(); receiver.select(.digitalVoice)
    receiver.settings.digitalVoiceProtocol = .nxdn48; receiver.applyDigitalVoicePreset()
    receiver.select(.morse); receiver.select(.digitalVoice)
    #expect(receiver.settings.digitalVoiceProtocol == .nxdn48)
    #expect(receiver.rfBandwidth == 6250 && receiver.rfModulation == .fm)
}

@Test func dgpsAudioCenterLeavesRoomForMixerImageRejection() throws {
    var settings = DecoderSettings(); settings.frequency = 800
    try settings.validated(sampleRate: 8000, mode: .dgps)
    settings.dgpsRate = .bps200
    let copy = try JSONDecoder().decode(DecoderSettings.self, from: JSONEncoder().encode(settings))
    #expect(copy.dgpsRate == .bps200)
    for center in [100.0, 3900] {
        settings.frequency = center
        #expect(throws: RadioError.self) { try settings.validated(sampleRate: 8000, mode: .dgps) }
    }
    settings.frequency = 85
    #expect(throws: RadioError.self) { try settings.validated(sampleRate: 8000, mode: .sitorA) }
}

@Test func pendingModesPreserveOldProfilesAndValidateBandEdges() throws {
    let legacy = try JSONDecoder().decode(DecoderSettings.self, from: Data("{}".utf8))
    #expect(legacy.mt63Variant == .b1000Long)
    for variant in MT63Variant.allCases {
        var settings = legacy; settings.mt63Variant = variant; settings.frequency = 1500
        try settings.validated(sampleRate: 48000, mode: .mt63)
        let decoded = try JSONDecoder().decode(DecoderSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.mt63Variant == variant)
    }
    var invalid = legacy; invalid.frequency = 800
    #expect(throws: RadioError.self) { try invalid.validated(sampleRate: 48000, mode: .mt63) }
    #expect(throws: RadioError.self) { try legacy.validated(sampleRate: 4000, mode: .ale) }
    #expect(RadioMode.ale.engineSampleRate == 8000 && RadioMode.mt63.engineSampleRate == 8000)
    #expect(RadioMode.ale.receptionProfile.modulation == .usb)
    #expect(RadioMode.sitorA.isAudioAvailable && RadioMode.gmdss.isAudioAvailable && RadioMode.dgps.isAudioAvailable)
    #expect(legacy.dgpsRate == .automatic)
}

@Test(arguments: [RadioMode.mt63, .ale, .sitorA, .dgps, .flex])
func pendingModeWorkerDecodesWAVThroughPackagedTransport(_ mode: RadioMode) async throws {
    let name = mode == .mt63 ? MT63Variant.b1000Long.fixtureName : SignalReference.matching(mode: mode, settings: DecoderSettings())!.fileName
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    var settings = DecoderSettings(); settings.frequency = mode.receptionProfile.center
    let box = PendingModeUpdates(), worker = RadioWorker()
    try await worker.decodeFile(url: url, mode: mode, settings: settings) { await box.receive($0) }
    let latest = try #require(await box.latest)
    #expect(latest.finished && latest.progress == 1)
    #expect(!latest.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    if mode == .mt63 || mode == .ale {
        #expect(!latest.engineRecords.isEmpty)
        #expect(latest.engineRecords.allSatisfy { $0.snrDB == nil && $0.crcValid == nil })
        #expect(latest.detail.contains(mode == .mt63 ? "MT63" : "ALE 2G"))
    } else if mode == .flex {
        #expect(latest.multimonRecords.first?.address == 1_234_567)
        #expect(latest.multimonRecords.first?.flex?.phase == "A")
    } else if mode == .dgps {
        #expect(latest.dgpsReceptions.count == 3)
        #expect(latest.dgpsReceptions.allSatisfy { $0.stationID == 777 })
        #expect(latest.dgpsReceptions.contains { $0.referencePosition != nil })
    } else { #expect(latest.text == "TEST SITOR A123\n") }
}

private func stereo48kCopy(of url: URL, to destination: URL) throws {
    let reader = try AudioFileReader(url: url)
    let resampler = try StreamingAudioResampler(sampleRate: reader.sampleRate, outputRate: 48000)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
    let file = try AVAudioFile(forWriting: destination, settings: format.settings)
    func write(_ audio: [Float]) throws {
        guard !audio.isEmpty else { return }
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count)))
        buffer.frameLength = AVAudioFrameCount(audio.count)
        let planes = try #require(buffer.floatChannelData)
        for index in audio.indices { planes[0][index] = 0; planes[1][index] = audio[index] }
        try file.write(from: buffer)
    }
    while let block = try reader.next() { try write(resampler.process(block)) }
    try write(resampler.finish())
}

@Test(arguments: [RadioMode.mt63, .ale, .sitorA, .dgps, .flex])
func pendingModeWorkerResamples48kStereoSelectedInput(_ mode: RadioMode) async throws {
    let name = mode == .mt63 ? MT63Variant.b1000Long.fixtureName : SignalReference.matching(mode: mode, settings: DecoderSettings())!.fileName
    let source = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("pending-mode-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: destination) }
    try stereo48kCopy(of: source, to: destination)
    var settings = DecoderSettings(); settings.frequency = mode.receptionProfile.center; settings.audioChannel = .channel(1)
    let box = PendingModeUpdates(), worker = RadioWorker()
    try await worker.decodeFile(url: destination, mode: mode, settings: settings) { await box.receive($0) }
    let latest = try #require(await box.latest)
    #expect(latest.channelCount == 2 && latest.finished)
    #expect(latest.text.contains(mode == .mt63 ? "CQ TEST MT63 123" : mode == .sitorA ? "TEST SITOR A123" : mode == .dgps ? "RWB DGPS TEST 014" : mode == .flex ? "CQ RADIOWORKBENCH FLEX TEST" : "RADIOWORKBENCH TEST"))
}

@Test(arguments: [RadioMode.mt63, .ale, .sitorA, .dgps, .flex])
func pendingModeWorkerPublishesBeforeLiveInputCloses(_ mode: RadioMode) async throws {
    let name = mode == .mt63 ? MT63Variant.b1000Long.fixtureName : SignalReference.matching(mode: mode, settings: DecoderSettings())!.fileName
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let ring = try AudioSampleRing(capacity: Int(file.length) + 8192), worker = RadioWorker(), box = PendingModeUpdates()
    ring.write(buffer)
    var settings = DecoderSettings(); settings.frequency = mode.receptionProfile.center
    let selected = settings
    let task = Task { try await worker.decodeLive(ring: ring, sampleRate: file.processingFormat.sampleRate, mode: mode, settings: selected) { await box.receive($0) } }
    defer { task.cancel() }
    let expected = mode == .mt63 ? "CQ TEST MT63 123" : mode == .sitorA ? "TEST SITOR A123" : mode == .dgps ? "RWB DGPS TEST 014" : mode == .flex ? "CQ RADIOWORKBENCH FLEX TEST" : "RADIOWORKBENCH TEST"
    for _ in 0..<100 {
        if await box.latest?.text.contains(expected) == true { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(await box.latest?.text.contains(expected) == true)
    #expect(await box.latest?.dropped == 0)
    task.cancel(); do { try await task.value } catch is CancellationError { }
}
