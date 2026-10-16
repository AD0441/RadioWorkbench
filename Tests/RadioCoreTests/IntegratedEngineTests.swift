import Foundation
import AVFoundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func engineFixture(_ name: String) throws -> URL { try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures")) }
private func runEngine(_ name: String, mode: RadioMode, settings: DecoderSettings = .init()) throws -> ExternalEngineSnapshot {
    let reader = try AudioFileReader(url: engineFixture(name)), resampler = try StreamingAudioResampler(sampleRate: reader.sampleRate, outputRate: mode == .digitalVoice ? 48000 : 12000)
    let session = try ExternalAudioEngine(mode: mode, settings: settings); defer { session.cancel() }
    while let samples = try reader.next() { try session.write(resampler.process(samples)) }
    try session.write(resampler.finish()); return try session.finish()
}
@Test(arguments: [RadioMode.ft8, .ft4]) func integratedFTXRecoversCRCValidatedMessage(_ mode: RadioMode) throws {
    let result = try runEngine(mode.rawValue + "_12000_cq_clean", mode: mode)
    let message = try #require(result.records.first)
    #expect(message.text == "CQ LU1ABC GF05" && message.crcValid == true)
    #expect(abs((message.frequencyHz ?? 0) - (mode == .ft8 ? 1500 : 1200)) < 5)
    #expect(message.snrDB == nil) // upstream sync score must never masquerade as SNR
    let data = try JSONEncoder().encode(message)
    #expect(try JSONDecoder().decode(AudioEngineRecord.self, from: data).text == message.text)
}
@Test(arguments: [RadioMode.ft8, .ft4]) func integratedFTXSilenceDoesNotCreateContacts(_ mode: RadioMode) throws {
    let process = try ExternalAudioEngine(mode: mode, settings: .init()); defer { process.cancel() }
    try process.write([Float](repeating: 0, count: mode == .ft8 ? 180000 : 90000))
    #expect(try process.finish().records.isEmpty)
}
@Test(.enabled(if: CWEngine.isSupported), arguments: [CWEngine.automatic, .neural]) func integratedCWKitReadsKnownCW(_ engine: CWEngine) throws {
    var settings = DecoderSettings(); settings.cwEngine = engine
    let result = try runEngine("morse_8000_mono_clean", mode: .morse, settings: settings)
    #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "CQ TEST 123")
    #expect(abs((result.records.last?.toneHz ?? 0) - 700) < 2)
    #expect(abs((result.records.last?.wpm ?? 0) - 20) < 2)
}
@Test func integratedMissingEnginesAndInvalidSettingsFailExplicitly() throws {
    #expect(throws: AudioEngineError.self) { try ExternalAudioEngine(mode: .ft8, settings: .init(), executableURL: URL(fileURLWithPath: "/tmp/missing-rwb-helper")) }
    var settings = DecoderSettings(); settings.ftxStartSeconds = .nan
    #expect(throws: RadioError.self) { try settings.validated(sampleRate: 48000, mode: .ft8) }
    #expect(throws: RadioError.self) { try DecoderSettings().validated(sampleRate: 8000, mode: .digitalVoice) }
    #expect(RadioWorker.nextFTXSlot(after: Date(timeIntervalSince1970: 16), seconds: 15).timeIntervalSince1970 == 30)
    #expect(RadioWorker.nextFTXSlot(after: Date(timeIntervalSince1970: 16), seconds: 7.5).timeIntervalSince1970 == 22.5)
}
@Test func integratedACARSApplicationsUseCompleteBlocksAndPreserveExport() throws {
    let process = try ACARSProcess(); defer { process.cancel() }
    for name in Array(repeating: ["acars_adsc_part1_12000", "acars_adsc_part2_12000"], count: 12).flatMap({ $0 }) {
        let reader = try AudioFileReader(url: engineFixture(name))
        while let samples = try reader.next() { try process.write(samples) }
    }
    let result = try process.finish()
    #expect(result.total == 24)
    #expect(result.messages.filter { $0.aircraftPosition != nil }.count == 12)
    #expect(result.messages.first?.applicationText == nil)
    #expect(result.messages.first?.applicationStatus == 2, "\(result.messages)")
    let message = try #require(result.messages.last)
    #expect(message.applicationText?.contains("ADS-C") == true)
    let pos = try #require(message.aircraftPosition)
    #expect(abs(pos.latitude - 52.0401764) < 1e-6 && abs(pos.longitude - 19.8038864) < 1e-6)
    #expect(pos.altitudeFeet == 36004)
    let decoded = try JSONDecoder().decode(ACARSMessage.self, from: JSONEncoder().encode(message))
    #expect(decoded.applicationJSON == message.applicationJSON)
}
@Test func integratedACARSOrphanFragmentDoesNotInventPosition() throws {
    let process = try ACARSProcess(); defer { process.cancel() }
    let reader = try AudioFileReader(url: engineFixture("acars_adsc_part2_12000"))
    while let samples = try reader.next() { try process.write(samples) }
    let result = try process.finish()
    #expect(result.total == 1 && result.messages.first?.aircraftPosition == nil && result.messages.first?.applicationText == nil)
}
@Test func integratedSGP4MatchesValladoVanguardReferenceAndRejectsLegacyDrag() throws {
    // Vallado/CelesTrak SGP4 verification satellite 00005, epoch 2000 day 179.78495062.
    let epoch = try #require(SatelliteElementParser.utcDate("2000-06-27T18:50:19.733568Z"))
    let orbit = TLEOrbit(name: "VANGUARD", catalogNumber: 5, epoch: epoch, meanMotionRevolutionsPerDay: 10.82419157,
        eccentricity: 0.1859667, inclinationDegrees: 34.2682, raanDegrees: 348.7242, argumentOfPerigeeDegrees: 331.7664, meanAnomalyDegrees: 19.3264, bstar: 2.8098e-5)
    let p = try #require(orbit.temePosition(at: epoch))
    #expect(abs(p.x - 7022.46529266) < 0.1)
    #expect(abs(p.y + 1400.08296755) < 0.1)
    #expect(abs(p.z - 0.03995155) < 0.1)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(orbit)) as? [String: Any]); object.removeValue(forKey: "bstar")
    let old = try JSONDecoder().decode(TLEOrbit.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.isValid && !old.propagationReady && old.position(at: epoch) == nil)
    let observer = try #require(orbit.position(at: epoch))
    let observation = try #require(orbit.observation(at: epoch, latitude: observer.latitude, longitude: observer.longitude))
    #expect(abs(observation.elevationDegrees - 90) < 1e-6)
    #expect(observation.dopplerHz(frequencyMHz: 145.8)?.isFinite == true)
    #expect(observation.dopplerHz(frequencyMHz: -1) == nil)
}
private actor EngineUpdateBox {
    var latest: RadioUpdate?
    func receive(_ update: RadioUpdate) { latest = update }
}
@Test(arguments: [RadioMode.ft8, .ft4]) func integratedFTXWorkerProcessesWAVAndFinalPartialSlot(_ mode: RadioMode) async throws {
    let worker = RadioWorker(), box = EngineUpdateBox()
    try await worker.decodeFile(url: engineFixture(mode.rawValue + "_12000_cq_clean"), mode: mode, settings: .init()) { await box.receive($0) }
    let update = try #require(await box.latest)
    #expect(update.finished && update.engineRecords.first?.text == "CQ LU1ABC GF05")
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["DSD_NEO_PATH"] != nil))
func integratedDSDReceivesM17PacketThroughPCMAndRejectsSilence() throws {
    var settings = DecoderSettings(); settings.digitalVoiceProtocol = .m17
    let result = try runEngine("m17_packet_48000_synthetic", mode: .digitalVoice, settings: settings)
    #expect(result.text.contains("SMS: Lorem ipsum"))
    #expect(result.text.contains("CRC - C: 2F6F; E: 2F6F"))
    let silence = try ExternalAudioEngine(mode: .digitalVoice, settings: settings); defer { silence.cancel() }
    try silence.write([Float](repeating: 0, count: 48000))
    #expect(try !silence.finish().text.contains("Sync: +M17"))
}

@Test func integratedACARSCPDLCAndInnerCRC() throws {
    for name in ["acars_cpdlc_12000", "acars_adsc_bad_inner_crc_12000"] {
        let process = try ACARSProcess(); defer { process.cancel() }
        let reader = try AudioFileReader(url: engineFixture(name))
        while let samples = try reader.next() { try process.write(samples) }
        let result = try process.finish(), message = try #require(result.messages.first)
        if name.contains("cpdlc") { #expect(message.applicationText?.contains("CPDLC") == true) }
        else { #expect(message.applicationJSON?.contains("\"crc_ok\":false") == true && message.aircraftPosition == nil) }
    }
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["DSD_NEO_PATH"] != nil))
func integratedDSDVoiceProducesPlayableWAV() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-voice-test-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    var settings = DecoderSettings(); settings.digitalVoiceProtocol = .m17
    let process = try ExternalAudioEngine(mode: .digitalVoice, settings: settings, voiceURL: url); defer { process.cancel() }
    let reader = try AudioFileReader(url: engineFixture("m17_voice_48000_synthetic"))
    while let samples = try reader.next() { try process.write(samples) }
    let result = try process.finish()
    #expect(result.text.contains("CODEC2:"))
    let voice = try AudioFileReader(url: url)
    #expect(voice.duration > 2 && voice.sampleRate == 8000)
    #expect(try voice.next()?.contains(where: { abs($0) > 0.01 }) == true)
}

@Test(.enabled(if: CWEngine.isSupported), arguments: [CWEngine.automatic, .neural])
func integratedCWKitTracksFrequencyAndSpeedAwayFromDefaults(_ engine: CWEngine) throws {
    var settings = DecoderSettings(); settings.cwEngine = engine
    let result = try runEngine("cwkit_12000_900hz_28wpm", mode: .morse, settings: settings)
    #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "CQ TEST 123")
    #expect(abs((result.records.last?.toneHz ?? 0) - 900) < 3)
    #expect(abs((result.records.last?.wpm ?? 0) - 28) < 3)
}
@Test(.enabled(if: CWEngine.isSupported)) func integratedCWKitPublishesWhileLiveInputRemainsOpen() async throws {
    let file = try AVAudioFile(forReading: engineFixture("morse_8000_mono_clean"), commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    let ring = try AudioSampleRing(capacity: Int(file.length) + 8192), box = EngineUpdateBox(), worker = RadioWorker()
    ring.write(buffer)
    var settings = DecoderSettings(); settings.cwEngine = .automatic
    let selected = settings
    let task = Task { try await worker.decodeLive(ring: ring, sampleRate: file.processingFormat.sampleRate, mode: .morse, settings: selected) { await box.receive($0) } }
    defer { task.cancel() }
    for _ in 0..<100 {
        if await box.latest?.text.contains("CQ TEST") == true { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(await box.latest?.text.contains("CQ TEST") == true)
    task.cancel(); do { try await task.value } catch is CancellationError { }
}
