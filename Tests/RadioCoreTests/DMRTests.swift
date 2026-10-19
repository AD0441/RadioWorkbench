import AVFoundation
import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private final class DMRVoiceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var energy = 0.0
    func receive(_ chunk: DigitalVoicePCMChunk) {
        lock.lock(); defer { lock.unlock() }
        frames += chunk.frameCount
        energy += chunk.samples.reduce(0) { $0 + Double($1 * $1) }
    }
    var value: (frames: Int, energy: Double) { lock.lock(); defer { lock.unlock() }; return (frames, energy) }
}

@Test func dmrConsoleHandlesANSIByteFragmentsAndSeparatesSlots() throws {
    var parser = DMRLogParser()
    let start = Date(timeIntervalSince1970: 1800000000)
    let log = "\u{1B}[32m18:09:27 Sync: +DMR MS/DM MODE/MONO | Color Code=07 | VLC\u{1B}[0m\n SLOT 1 TGT=9990 SRC=3025209 Private Call\n"
    for byte in log.utf8 { parser.consume(Data([byte]), at: start) }
    #expect(parser.status.slots[0].sourceID == 3025209)
    #expect(parser.status.slots[0].targetID == 9990 && parser.status.slots[0].colorCode == 7)
    #expect(parser.status.slots[0].callKind == "Individual")
    #expect(parser.status.slots[1].sourceID == nil)
    // Synthetic console case: the independent public recording has only TS1.
    parser.consume(Data("Sync: +DMR  slot1 [SLOT2] | Color Code=03 | VC2\n SLOT 2 TGT=123 SRC=456 Group Call\n".utf8), at: start.addingTimeInterval(1))
    #expect(parser.status.slots[1].sourceID == 456 && parser.status.slots[1].targetID == 123)
    #expect(parser.status.slots[1].colorCode == 3 && parser.status.slots[1].callKind == "Grupo")
    #expect(parser.status.slots[0].sourceID == 3025209 && parser.status.slots[0].identityAt == start)
    let result = try JSONDecoder().decode(DMRStatus.self, from: JSONEncoder().encode(parser.status))
    #expect(result == parser.status)
}

@Test func dmrConsoleRejectsBadOrUnrelatedIdentitiesAndUnknownColor() {
    var parser = DMRLogParser(); let date = Date()
    parser.consume(Data("Sync: +DMR [SLOT1] | Color Code=07 | VC1\n SLOT 1 TGT=12 SRC=34 Group Call\n".utf8), at: date)
    parser.consume(Data("Sync: +DMR [SLOT1] | Color Code=XX | VC1\n SLOT 1 TGT=99 SRC=88 FLCO FEC ERR\n SLOT 1 TGT=50 SRC=60 Group Call\n".utf8), at: date.addingTimeInterval(1))
    #expect(parser.status.slots[0].sourceID == 34 && parser.status.slots[0].colorCode == nil)
    #expect(parser.status.slots[0].identityAt == date && parser.status.rejectedLines == 1)
    parser.consume(Data("Sync: +P25 | Color Code=15\n SLOT 2 TGT=999 SRC=123 Group Call\n".utf8), at: date.addingTimeInterval(1))
    #expect(parser.status.slots[1].targetID == nil)
    parser.consume(Data("Sync: +DMR [SLOT2] | Color Code=16 | VC1\n SLOT 2 TGT=16777216 SRC=4 Group Call\nSync: no sync\n SLOT 2 TGT=5 SRC=6 Group Call\n".utf8), at: date.addingTimeInterval(6))
    #expect(parser.status.slots[1].sourceID == nil && parser.status.slots[1].colorCode == nil)
    parser.consume(Data(repeating: 65, count: 20000), at: date)
    parser.consume(Data("\nSLOT 2 TGT=5 SRC=6 Group Call\n".utf8), at: date)
    #expect(parser.status.slots[1].sourceID == nil)
}

@Test func dmrPCMRecoversStereoAcrossUnalignedReadsAndSignedExtremes() {
    let bytes: [UInt8] = [0, 128, 255, 127, 0, 0, 0, 64, 0, 192, 0, 0]
    var decoder = DMRVoicePCMDecoder(), result: [DigitalVoicePCMChunk] = []
    for byte in bytes { result += decoder.consume(Data([byte])) }
    #expect(decoder.frames == 3 && decoder.incompleteBytes == 0)
    let samples = result.flatMap(\.samples)
    #expect(samples == [-1, Float(32767) / 32768, 0, 0.5, -0.5, 0])
    #expect(result.allSatisfy { $0.channels == 2 && $0.sampleRate == 8000 })
    _ = decoder.consume(Data([1, 2, 3])); #expect(decoder.incompleteBytes == 3 && decoder.frames == 3)
    let final = decoder.consume(Data([4])); #expect(final.first?.frameCount == 1 && decoder.frames == 4)
}

@Test func dmrSettingsRemainCompatibleWithSavedReceptions() throws {
    var settings = try JSONDecoder().decode(DecoderSettings.self, from: Data("{}".utf8))
    #expect(settings.dmrSlotSelection == .both && !settings.dmrMonitorVoice)
    settings.dmrSlotSelection = .ts2; settings.dmrMonitorVoice = true
    #expect(try JSONDecoder().decode(DecoderSettings.self, from: JSONEncoder().encode(settings)) == settings)
    #expect(DMRSlotSelection.ts1.synthesisMask == "1" && DMRSlotSelection.ts2.synthesisMask == "2" && DMRSlotSelection.both.synthesisMask == "3")
}

@Test(.enabled(if: ExternalAudioEngine.dsdSupported))
func dmrTransportSeparatesBinaryVoiceFromFragmentedConsoleBeforeEOF() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-dmr-transport-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let helper = root.appendingPathComponent("helper"), args = root.appendingPathComponent("args")
    let script = """
    #!/bin/sh
    printf '%s\\n' "$@" > '\(args.path)'
    printf '18:09:27 Sync: +DMR MS/DM MODE/MONO | Color Code=07 | VLC\\n SLOT 1 TGT=9990 SRC=3025209 Private Call\\n' >&2
    printf '\\001'
    sleep 0.03
    printf '\\000\\377\\177\\000\\200\\000\\000'
    cat >/dev/null
    """
    try script.write(to: helper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    var settings = DecoderSettings(); settings.dmrSlotSelection = .ts1
    let box = DMRVoiceBox()
    let engine = try ExternalAudioEngine(mode: .digitalVoice, settings: settings, executableURL: helper, voiceOutput: { box.receive($0) })
    defer { engine.cancel() }
    try engine.write([Float](repeating: 0, count: 100))
    for _ in 0..<150 { if box.value.frames == 2 { break }; try await Task.sleep(for: .milliseconds(20)) }
    #expect(box.value.frames == 2, "PCM must arrive while stdin remains open")
    let result = try engine.finish()
    let finalization = ProcessInfo.processInfo.systemUptime
    engine.finishVoice()
    #expect(ProcessInfo.processInfo.systemUptime - finalization < 0.2, "A completed process must remain joinable without consuming a termination signal")
    #expect(result.voiceFrames == 2 && result.dmrStatus?.slots[0].sourceID == 3025209)
    #expect(!result.text.contains("\u{0}") && result.text.contains("SLOT 1"))
    let argv = try String(contentsOf: args, encoding: .utf8)
    #expect(argv.contains("-V\n1\n") && argv.contains("-o\n-\n") && !argv.contains("-z\n"))
}

@Test func dmrOutputGraphRendersStereoAndBoundsPendingAudioWithoutSpeakers() throws {
    let monitor = try DMRVoiceMonitor(offline: true); defer { monitor.stop() }
    var decoder = DMRVoicePCMDecoder()
    let bytes = Data(Array(repeating: [UInt8](arrayLiteral: 0, 64, 0, 192), count: 2048).flatMap { $0 })
    for _ in 0..<12 { for chunk in decoder.consume(bytes) { monitor.enqueue(chunk) } }
    #expect(monitor.snapshot.queued <= 16000 && monitor.snapshot.dropped > 0)
    var energy = 0.0
    for _ in 0..<3 {
        let buffer = try monitor.renderOffline(frames: 1024)
        let channels = try #require(buffer.floatChannelData)
        for i in 0..<Int(buffer.frameLength) { energy += Double(channels[0][i] * channels[0][i] + channels[1][i] * channels[1][i]) }
    }
    #expect(energy > 100)
    monitor.stop()
    for chunk in decoder.consume(bytes) { monitor.enqueue(chunk) }
    #expect(monitor.snapshot.queued == 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["DMR_REFERENCE_WAV"] != nil && ProcessInfo.processInfo.environment["DSD_NEO_PATH"] != nil), arguments: DMRSlotSelection.allCases)
func dmrIndependentReferenceMatchesKnownCallAndSlotSynthesis(_ slot: DMRSlotSelection) throws {
    let source = try #require(ProcessInfo.processInfo.environment["DMR_REFERENCE_WAV"])
    var settings = DecoderSettings(); settings.dmrSlotSelection = slot
    let box = DMRVoiceBox()
    let engine = try ExternalAudioEngine(mode: .digitalVoice, settings: settings, voiceOutput: { box.receive($0) })
    defer { engine.cancel() }
    let reader = try AudioFileReader(url: URL(fileURLWithPath: source))
    while let block = try reader.next() { try engine.write(block) }
    let result = try engine.finish(), status = try #require(result.dmrStatus)
    #expect(status.slots[0].sourceID == 3025209 && status.slots[0].targetID == 9990 && status.slots[0].colorCode == 7)
    #expect(status.slots[1].sourceID == nil)
    #expect(result.voiceFrames > 100000 && box.value.frames == Int(result.voiceFrames))
    #expect(slot == .ts2 ? box.value.energy == 0 : box.value.energy > 1)
}

private actor DMRWorkerUpdates {
    var latest: RadioUpdate?
    func receive(_ value: RadioUpdate) { latest = value }
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["DMR_REFERENCE_WAV"] != nil && ProcessInfo.processInfo.environment["DSD_NEO_PATH"] != nil))
func dmrLiveWorkerDrainsPCMAndPublishesKnownCallAtNetworkEOF() async throws {
    let source = try #require(ProcessInfo.processInfo.environment["DMR_REFERENCE_WAV"])
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: source), commonFormat: .pcmFormatFloat32, interleaved: false)
    let audio = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: audio)
    let ring = try AudioSampleRing(capacity: Int(file.length) + 8192)
    ring.write(audio); ring.finish()
    let worker = RadioWorker(), updates = DMRWorkerUpdates(), voice = DMRVoiceBox()
    try await worker.decodeLive(ring: ring, sampleRate: 48000, mode: .digitalVoice, settings: .init(), source: "Independent DMR reference", voiceOutput: { voice.receive($0) }) { await updates.receive($0) }
    let final = try #require(await updates.latest)
    defer { if let url = final.voiceURL { try? FileManager.default.removeItem(at: url) } }
    #expect(final.finished && final.dropped == 0 && final.samplesReceived == UInt64(file.length))
    #expect(final.dmrStatus?.slots[0].sourceID == 3025209 && final.dmrStatus?.slots[1].sourceID == nil)
    #expect(final.voiceFrames > 100000 && final.voiceFrames == UInt64(voice.value.frames))
    let wav = try AudioFileReader(url: #require(final.voiceURL))
    #expect(wav.sampleRate == 8000 && wav.channelCount == 2)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["DMR_REFERENCE_WAV"] != nil && ProcessInfo.processInfo.environment["DSD_NEO_PATH"] != nil))
func dmrLiveWorkerCancellationFinalizesVoiceWithoutAnInputEOF() async throws {
    let source = try #require(ProcessInfo.processInfo.environment["DMR_REFERENCE_WAV"])
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: source), commonFormat: .pcmFormatFloat32, interleaved: false)
    let audio = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: audio)
    let ring = try AudioSampleRing(capacity: Int(file.length) + 8192)
    ring.write(audio) // Source deliberately remains open, as during reception.
    let worker = RadioWorker(), updates = DMRWorkerUpdates(), voice = DMRVoiceBox()
    let task = Task {
        try await worker.decodeLive(ring: ring, sampleRate: 48000, mode: .digitalVoice, settings: .init(), voiceOutput: { voice.receive($0) }) { await updates.receive($0) }
    }
    defer { task.cancel() }
    for _ in 0..<300 { if voice.value.frames > 100000 { break }; try await Task.sleep(for: .milliseconds(50)) }
    #expect(voice.value.frames > 100000)
    let before = ProcessInfo.processInfo.systemUptime
    task.cancel()
    #expect(ProcessInfo.processInfo.systemUptime - before < 1, "Requesting cancellation must not wait for the voice finalization timeout")
    do { try await task.value; Issue.record("Live reception should end by cancellation") } catch is CancellationError { }
    let update = try #require(await updates.latest), url = try #require(update.voiceURL)
    defer { try? FileManager.default.removeItem(at: url) }
    let wav = try AudioFileReader(url: url)
    #expect(wav.sampleRate == 8000 && wav.channelCount == 2 && wav.duration > 1)
    #expect(!ring.isFinished, "Cancel closes the helper; it does not pretend the producer sent EOF")
}

@Test(.enabled(if: ExternalAudioEngine.dsdSupported))
func dmrCancellationBoundsAnOwnedHelperThatIgnoresEOFAndSIGTERM() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-stubborn-decoder-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("helper")
    try """
    #!/usr/bin/python3
    import signal, sys, time
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print('ready', file=sys.stderr, flush=True)
    while True: time.sleep(0.1)
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let engine = try ExternalAudioEngine(mode: .digitalVoice, settings: .init(), executableURL: script)
    defer { engine.cancel() }
    for _ in 0..<100 { if engine.snapshot.text.contains("ready") { break }; try await Task.sleep(for: .milliseconds(30)) }
    #expect(engine.snapshot.text.contains("ready"))
    let started = ProcessInfo.processInfo.systemUptime
    engine.cancel()
    #expect(throws: AudioEngineError.self) { try engine.finish() }
    #expect(ProcessInfo.processInfo.systemUptime - started < 5, "The owned child must not outlive the bounded cancellation grace period")
}
