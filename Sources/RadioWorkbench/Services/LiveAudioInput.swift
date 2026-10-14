import AVFoundation
import AudioToolbox
import CoreAudio
import RadioCore

@MainActor
final class LiveAudioInput {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private var generation = UUID()
    var configurationChanged: (@MainActor () -> Void)?
    func start(deviceID: UInt32 = 0, channel: AudioChannelSelection = .mix) async throws -> (ring: AudioSampleRing, sampleRate: Double, channels: Int) {
        stop()
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard granted else { throw RadioError.microphoneDenied }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if deviceID != 0 {
            // Bind only this engine's I/O unit; keep the system default untouched.
            let status: OSStatus
            if #available(macOS 27.0, *) {
                status = input.withAudioUnit { unit in
                    guard let unit else { return kAudio_ParamError }
                    return Self.select(deviceID, on: unit)
                }
            } else {
                guard let unit = input.audioUnit else { throw RadioError.invalidAudio }
                status = Self.select(deviceID, on: unit)
            }
            guard status == noErr else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                    NSLocalizedDescriptionKey: "No se pudo seleccionar la entrada de audio (CoreAudio: \(status))."
                ])
            }
        }
        var tapInstalled = false, committed = false
        defer {
            if !committed { engine.stop(); if tapInstalled { input.removeTap(onBus: 0) } }
        }
        var stream: (ring: AudioSampleRing, sampleRate: Double, channels: Int)?
        // CoreAudio can create/reformat a private aggregate while starting I/O
        // with a selected input and the existing output. Stabilize it before
        // handing PCM to a decoder; never join blocks from different rates.
        for _ in 0..<3 {
            try Task.checkCancellation()
            let format = input.inputFormat(forBus: 0)
            try Self.validate(format)
            try channel.validate(channelCount: Int(format.channelCount))
            let ring = try AudioSampleRing(channel: channel)
            if #available(macOS 27.0, *) {
                try input.installAudioTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in ring.write(buffer) }
            } else {
                input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.legacyTap(ring: ring))
            }
            tapInstalled = true
            try engine.start()
            try await Task.sleep(for: .milliseconds(500))
            if engine.isRunning, Self.matches(input, format), ring.written == 0 {
                try await Task.sleep(for: .milliseconds(500))
            }
            if engine.isRunning, Self.matches(input, format), ring.written > 0 {
                stream = (ring, format.sampleRate, Int(format.channelCount)); break
            }
            engine.stop(); input.removeTap(onBus: 0); tapInstalled = false
        }
        guard let stream else {
            throw NSError(domain: "RadioWorkbench.Audio", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "La entrada no estabilizó el formato o no entregó muestras. Actualiza los dispositivos y vuelve a pulsar Escuchar."
            ])
        }
        self.engine = engine
        committed = true
        let token = UUID(); generation = token
        let expectedRate = stream.sampleRate, expectedChannels = stream.channels
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            // The engine's internal notification queue must not stop/deallocate it.
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, let active = self.engine else { return }
                let actual = active.inputNode.outputFormat(forBus: 0)
                if active.isRunning, actual.sampleRate == expectedRate, Int(actual.channelCount) == expectedChannels { return }
                self.configurationChanged?()
            }
        }
        return stream
    }
    private static func matches(_ input: AVAudioInputNode, _ expected: AVAudioFormat) -> Bool {
        let hardware = input.inputFormat(forBus: 0), output = input.outputFormat(forBus: 0)
        return hardware.sampleRate == expected.sampleRate && hardware.channelCount == expected.channelCount
            && output.sampleRate == expected.sampleRate && output.channelCount == expected.channelCount
    }
    private static func validate(_ format: AVAudioFormat) throws {
        guard format.sampleRate.isFinite, (4000...384000).contains(format.sampleRate),
              (1...32).contains(format.channelCount), format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else {
            throw NSError(domain: "RadioWorkbench.Audio", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "La entrada no ofrece PCM Float32 válido: \(format.sampleRate) Hz, \(format.channelCount) canal(es). Actualiza los dispositivos y vuelve a seleccionarla."
            ])
        }
    }
    nonisolated private static func legacyTap(ring: AudioSampleRing) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in ring.write(buffer) }
    }
    private static func select(_ deviceID: AudioDeviceID, on unit: AudioUnit) -> OSStatus {
        var selected = deviceID
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global, 0, &selected,
                                    UInt32(MemoryLayout<AudioDeviceID>.size))
    }
    func stop() {
        generation = UUID()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        guard let engine else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0); self.engine = nil
    }
}
