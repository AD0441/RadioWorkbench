import Foundation
import RadioCore

extension RadioWorker {
    func decodeAdditionalFile(url: URL, mode: RadioMode, settings: DecoderSettings, update: @Sendable (RadioUpdate) async -> Void) async throws {
        let reader = try AudioFileReader(url: url, channel: settings.audioChannel)
        try settings.validated(sampleRate: reader.sampleRate, mode: mode)
        let rate = mode == .digitalVoice ? 48000.0 : 12000.0
        let resampler = try StreamingAudioResampler(sampleRate: reader.sampleRate, outputRate: rate)
        let ftx = mode == .ft8 || mode == .ft4
        let voice = mode == .digitalVoice ? FileManager.default.temporaryDirectory.appendingPathComponent("RadioWorkbench-voice-\(UUID().uuidString).wav") : nil
        let engine = ftx ? nil : try ExternalAudioEngine(mode: mode, settings: settings, voiceURL: voice)
        defer { engine?.cancel() }
        var buffer: [Float] = [], records: [AudioEngineRecord] = [], last = 0.0, frame: SpectrumFrame?
        let spectrum = SpectrumAnalyzer(), window = Int((mode == .ft4 ? 7.5 : 15) * rate)
        var skip = Int(settings.ftxStartSeconds * rate), elapsedSamples = 0
        func consume(_ samples: [Float]) throws {
            if ftx {
                let drop = min(skip, samples.count); skip -= drop
                buffer.append(contentsOf: samples.dropFirst(drop))
                while buffer.count >= window {
                    records += try decodeFTX(Array(buffer.prefix(window)), mode: mode, settings: settings)
                    records = Array(records.suffix(200)); buffer.removeFirst(window)
                }
            } else { try engine?.write(samples) }
        }
        try await withTaskCancellationHandler {
            while let samples = try reader.next() {
                try Task.checkCancellation()
                elapsedSamples += samples.count
                if mode == .digitalVoice && Double(elapsedSamples) / reader.sampleRate > 1800 { throw AudioEngineError.failed("Límite de 30 minutos por sesión de voz. Divide el archivo antes de continuar.") }
                try consume(resampler.process(samples))
                let now = ProcessInfo.processInfo.systemUptime
                if now - last >= 0.2 {
                    frame = spectrum.analyze(samples, sampleRate: reader.sampleRate)
                    let snapshot = engine?.snapshot
                    await update(RadioUpdate(text: ftx ? records.map(\.monitorLine).joined(separator: "\n") : snapshot?.text ?? "", frame: frame, progress: reader.progress,
                        source: url.lastPathComponent, detail: engineDetail(mode, settings: settings, snapshot: snapshot), channelCount: reader.channelCount, engineRecords: ftx ? records : snapshot?.records ?? [], voiceURL: voice))
                    last = now
                }
            }
            try consume(resampler.finish())
            // A WAV may end before the slot boundary; do not silently discard its final transmission.
            if ftx && buffer.count > Int(rate) { records += try decodeFTX(buffer, mode: mode, settings: settings); records = Array(records.suffix(200)) }
            let result = try engine?.finish()
            await update(RadioUpdate(text: ftx ? records.map(\.monitorLine).joined(separator: "\n") : result?.text ?? "", frame: frame, progress: 1,
                source: url.lastPathComponent, detail: engineDetail(mode, settings: settings, snapshot: result), finished: true, channelCount: reader.channelCount,
                engineRecords: ftx ? records : result?.records ?? [], voiceURL: voice))
        } onCancel: { if mode == .digitalVoice { engine?.finishVoice() } else { engine?.cancel() } }
    }
    func decodeAdditionalLive(ring: AudioSampleRing, sampleRate: Double, mode: RadioMode, settings: DecoderSettings, source: String, update: @Sendable (RadioUpdate) async -> Void) async throws {
        try settings.validated(sampleRate: sampleRate, mode: mode)
        let ftx = mode == .ft8 || mode == .ft4, rate = mode == .digitalVoice ? 48000.0 : 12000.0
        var voice = mode == .digitalVoice ? FileManager.default.temporaryDirectory.appendingPathComponent("RadioWorkbench-voice-\(UUID().uuidString).wav") : nil
        var engine = ftx ? nil : try ExternalAudioEngine(mode: mode, settings: settings, voiceURL: voice)
        var resampler = try StreamingAudioResampler(sampleRate: sampleRate, outputRate: rate)
        defer { if mode == .digitalVoice { engine?.finishVoice() } else { engine?.cancel() } }
        var retainedText = ""
        var storage = [Float](repeating: 0, count: 8192), buffer: [Float] = [], records: [AudioEngineRecord] = []
        let spectrum = SpectrumAnalyzer(), seconds = mode == .ft4 ? 7.5 : 15.0, window = Int((mode == .ft4 ? 7.5 : 15) * rate)
        var slot = Self.nextFTXSlot(after: Date(), seconds: seconds)
        var skip = max(0, Int(slot.timeIntervalSinceNow * rate)), previousDrop: UInt64 = 0, last = 0.0
        let started = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            if mode == .digitalVoice && ProcessInfo.processInfo.systemUptime - started > 1800 { throw AudioEngineError.failed("Sesión de voz de 30 minutos completada. Inicia otra sesión para continuar.") }
            let count = ring.read(into: &storage), samples = Array(storage.prefix(count))
            if ring.dropped != previousDrop {
                buffer.removeAll(keepingCapacity: true); previousDrop = ring.dropped
                retainedText = String((retainedText + (engine?.snapshot.text ?? "") + "\n[Interrupción de audio]\n").suffix(20000))
                if mode == .digitalVoice {
                    engine?.finishVoice()
                    if let previous = voice { try? FileManager.default.removeItem(at: previous) }
                    voice = FileManager.default.temporaryDirectory.appendingPathComponent("RadioWorkbench-voice-\(UUID().uuidString).wav")
                } else { engine?.cancel() }
                engine = ftx ? nil : try ExternalAudioEngine(mode: mode, settings: settings, voiceURL: voice)
                resampler = try StreamingAudioResampler(sampleRate: sampleRate, outputRate: rate)
                slot = Self.nextFTXSlot(after: Date(), seconds: seconds); skip = max(0, Int(slot.timeIntervalSinceNow * rate))
            }
            if count > 0 {
                let mapped = resampler.process(samples)
                if ftx {
                    let drop = min(skip, mapped.count); skip -= drop; buffer.append(contentsOf: mapped.dropFirst(drop))
                    while buffer.count >= window {
                        var decoded = try decodeFTX(Array(buffer.prefix(window)), mode: mode, settings: settings)
                        for index in decoded.indices { decoded[index].slotUTC = slot }
                        records = Array((records + decoded).suffix(200)); buffer.removeFirst(window); slot = slot.addingTimeInterval(seconds)
                    }
                } else {
                    let active = engine
                    try await withTaskCancellationHandler { try active?.write(mapped) } onCancel: { if mode == .digitalVoice { active?.finishVoice() } else { active?.cancel() } }
                }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now - last >= 0.2 {
                let snapshot = engine?.snapshot
                await update(RadioUpdate(text: ftx ? records.map(\.monitorLine).joined(separator: "\n") : retainedText + (snapshot?.text ?? ""), frame: count > 0 ? spectrum.analyze(samples, sampleRate: sampleRate) : nil,
                    progress: 0, source: source, detail: ftx ? "Esperando ventanas UTC de \(seconds) s · \(buffer.count / 12000) s recibidos · sincroniza el reloj del Mac" : engineDetail(mode, settings: settings, snapshot: snapshot),
                    dropped: ring.dropped, samplesReceived: ring.written + ring.dropped, engineRecords: ftx ? records : snapshot?.records ?? [], voiceURL: voice))
                last = now
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    static func nextFTXSlot(after date: Date, seconds: Double) -> Date { Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / seconds) + 1) * seconds) }
    private func decodeFTX(_ samples: [Float], mode: RadioMode, settings: DecoderSettings) throws -> [AudioEngineRecord] {
        let process = try ExternalAudioEngine(mode: mode, settings: settings)
        defer { process.cancel() }
        try process.write(samples)
        return try process.finish().records
    }
    private func engineDetail(_ mode: RadioMode, settings: DecoderSettings, snapshot: ExternalEngineSnapshot?) -> String {
        if mode == .ft8 || mode == .ft4 { return "ft8_lib · LDPC + CRC · puntuación de sincronía; SNR no estimado" }
        if mode == .digitalVoice { return "DSD-neo · \(settings.digitalVoiceProtocol.rawValue) · voz WAV disponible al detener · solo canal sintonizado" }
        if let latest = snapshot?.records.last { return String(format: "%@ · tono %.0f Hz · %.1f WPM · SNR %.1f dB", settings.cwEngine.rawValue, latest.toneHz ?? 0, latest.wpm ?? 0, latest.snrDB ?? 0) }
        return settings.cwEngine.rawValue
    }
}
