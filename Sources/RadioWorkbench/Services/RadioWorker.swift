import Foundation
import RadioCore

struct RadioUpdate: Sendable {
    var text: String
    var frame: SpectrumFrame?
    var progress: Double
    var source: String
    var detail: String
    var finished = false
    var dropped: UInt64 = 0
    var image: RadioImage? = nil
    var channelCount: Int? = nil
    var acarsMessages: [ACARSMessage] = []
    var samplesReceived: UInt64 = 0
    var sstvCalibration: SSTVCalibration?
    var multimonRecords: [MultimonRecord] = []
}

actor RadioWorker {
    func decodeFile(url: URL, mode: RadioMode, settings: DecoderSettings,
                    update: @Sendable (RadioUpdate) async -> Void) async throws {
        if mode == .acars { try await decodeACARSFile(url: url, settings: settings, update: update); return }
        if mode.isMultimon { try await decodeMultimonFile(url: url, mode: mode, settings: settings, update: update); return }
        let reader = try AudioFileReader(url: url, channel: settings.audioChannel)
        let decoder = try DecoderEngine(mode: mode, sampleRate: reader.sampleRate, settings: settings)
        let spectrum = SpectrumAnalyzer()
        let started = ProcessInfo.processInfo.systemUptime
        var lastUpdate = started - 1
        var lastFrame: SpectrumFrame?
        let detail = "\(Int(reader.sampleRate)) Hz · \(reader.channelCount) canal(es) · \(settings.audioChannel.label) · \(String(format: "%.1f", reader.duration)) s"
        while let samples = try reader.next() {
            try Task.checkCancellation()
            decoder.process(samples)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastUpdate >= 0.1 {
                lastFrame = spectrum.analyze(samples, sampleRate: reader.sampleRate)
                await update(RadioUpdate(text: decoder.text, frame: lastFrame, progress: reader.progress, source: url.lastPathComponent, detail: detail + (decoder.status.isEmpty ? "" : " · " + decoder.status), image: decoder.image, channelCount: reader.channelCount, sstvCalibration: decoder.sstvCalibration))
                lastUpdate = now
            }
        }
        try Task.checkCancellation()
        decoder.finish()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        await update(RadioUpdate(text: decoder.text, frame: lastFrame, progress: 1, source: url.lastPathComponent,
                                 detail: detail + " · proceso \(String(format: "%.2f", elapsed)) s" + (decoder.status.isEmpty ? "" : " · " + decoder.status), finished: true, image: decoder.image, channelCount: reader.channelCount, sstvCalibration: decoder.sstvCalibration))
    }
    func decodeLive(ring: AudioSampleRing, sampleRate: Double, mode: RadioMode, settings: DecoderSettings, source: String = "Entrada de audio",
                    update: @Sendable (RadioUpdate) async -> Void) async throws {
        if mode == .acars { try await decodeACARSLive(ring: ring, sampleRate: sampleRate, settings: settings, source: source, update: update); return }
        if mode.isMultimon { try await decodeMultimonLive(ring: ring, sampleRate: sampleRate, mode: mode, settings: settings, source: source, update: update); return }
        var decoder = try DecoderEngine(mode: mode, sampleRate: sampleRate, settings: settings)
        let recording = try AudioDiagnosticRecorder.requested(rate: sampleRate, mode: mode)
        let spectrum = SpectrumAnalyzer()
        var storage = [Float](repeating: 0, count: 8192)
        var lastUpdate = 0.0
        var previousDrop: UInt64 = 0
        var retainedText = ""
        while !Task.isCancelled {
            let count = ring.read(into: &storage)
            if count > 0 {
                let dropped = ring.dropped
                if dropped != previousDrop {
                    retainedText = String((retainedText + decoder.text + "\n[Interrupción de audio]\n").suffix(32000))
                    decoder = try DecoderEngine(mode: mode, sampleRate: sampleRate, settings: settings)
                    previousDrop = dropped
                }
                let samples = Array(storage.prefix(count))
                try recording?.write(samples)
                decoder.process(samples)
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastUpdate >= 0.1 {
                    await update(RadioUpdate(text: retainedText + decoder.text, frame: spectrum.analyze(samples, sampleRate: sampleRate), progress: 0,
                                             source: source, detail: "\(Int(sampleRate)) Hz · \(settings.audioChannel.label) · recepción en vivo" + (decoder.status.isEmpty ? "" : " · " + decoder.status), dropped: dropped, image: decoder.image, samplesReceived: ring.written + ring.dropped, sstvCalibration: decoder.sstvCalibration))
                    lastUpdate = now
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func decodeACARSFile(url: URL, settings: DecoderSettings, update: @Sendable (RadioUpdate) async -> Void) async throws {
        let reader = try AudioFileReader(url: url, channel: settings.audioChannel)
        let resampler = try ACARSAudioResampler(sampleRate: reader.sampleRate)
        let session = try ACARSProcess(), spectrum = SpectrumAnalyzer()
        let started = ProcessInfo.processInfo.systemUptime
        let detail = "\(Int(reader.sampleRate)) Hz · \(reader.channelCount) canal(es) · \(settings.audioChannel.label) · \(String(format: "%.1f", reader.duration)) s"
        var lastUpdate = started - 1, frame: SpectrumFrame?
        defer { session.cancel() }
        try await withTaskCancellationHandler {
            while let samples = try reader.next() {
                try Task.checkCancellation(); try session.write(resampler.process(samples))
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastUpdate >= 0.1 {
                    frame = spectrum.analyze(samples, sampleRate: reader.sampleRate)
                    let result = session.snapshot
                    await update(RadioUpdate(text: result.text, frame: frame, progress: reader.progress, source: url.lastPathComponent, detail: detail + " · " + result.status, channelCount: reader.channelCount, acarsMessages: result.messages))
                    lastUpdate = now
                }
            }
            try Task.checkCancellation(); try session.write(resampler.finish())
            let result = try session.finish()
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            await update(RadioUpdate(text: result.text, frame: frame, progress: 1, source: url.lastPathComponent, detail: detail + " · proceso \(String(format: "%.2f", elapsed)) s · " + result.status, finished: true, channelCount: reader.channelCount, acarsMessages: result.messages))
        } onCancel: { session.cancel() }
    }

    private func decodeACARSLive(ring: AudioSampleRing, sampleRate: Double, settings: DecoderSettings, source: String, update: @Sendable (RadioUpdate) async -> Void) async throws {
        var session = try ACARSProcess()
        var resampler = try ACARSAudioResampler(sampleRate: sampleRate)
        let spectrum = SpectrumAnalyzer()
        var storage = [Float](repeating: 0, count: 8192), retained: [ACARSMessage] = []
        var lastUpdate = 0.0, previousDrop: UInt64 = 0
        defer { session.cancel() }
        while !Task.isCancelled {
            let count = ring.read(into: &storage)
            if count > 0 {
                if ring.dropped != previousDrop {
                    retained = Array((retained + session.snapshot.messages).suffix(100)); session.cancel()
                    session = try ACARSProcess(); resampler = try ACARSAudioResampler(sampleRate: sampleRate)
                    previousDrop = ring.dropped
                }
                let samples = Array(storage.prefix(count))
                let active = session
                try await withTaskCancellationHandler { try active.write(resampler.process(samples)) } onCancel: { active.cancel() }
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastUpdate >= 0.1 {
                    let result = session.snapshot
                    let messages = Array((retained + result.messages).suffix(200))
                    await update(RadioUpdate(text: messages.map(\.monitorLine).joined(separator: "\n"), frame: spectrum.analyze(samples, sampleRate: sampleRate), progress: 0, source: source, detail: "\(Int(sampleRate)) Hz · \(settings.audioChannel.label) · PCM continuo → 12000 Hz · " + result.status, dropped: ring.dropped, acarsMessages: messages, samplesReceived: ring.written + ring.dropped))
                    lastUpdate = now
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func decodeMultimonFile(url: URL, mode: RadioMode, settings: DecoderSettings, update: @Sendable (RadioUpdate) async -> Void) async throws {
        let reader = try AudioFileReader(url: url, channel: settings.audioChannel)
        try settings.validated(sampleRate: reader.sampleRate, mode: mode)
        let resampler = try StreamingAudioResampler(sampleRate: reader.sampleRate, outputRate: 22050)
        let session = try MultimonProcess(mode: mode, settings: settings), spectrum = SpectrumAnalyzer()
        var lastUpdate = 0.0, frame: SpectrumFrame?
        defer { session.cancel() }
        try await withTaskCancellationHandler {
            while let samples = try reader.next() {
                try Task.checkCancellation(); try session.write(resampler.process(samples))
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastUpdate >= 0.1 {
                    let result = session.snapshot; frame = spectrum.analyze(samples, sampleRate: reader.sampleRate)
                    await update(RadioUpdate(text: result.text, frame: frame, progress: reader.progress, source: url.lastPathComponent,
                        detail: "\(Int(reader.sampleRate)) Hz · \(settings.audioChannel.label) · " + result.status,
                        channelCount: reader.channelCount, multimonRecords: result.records))
                    lastUpdate = now
                }
            }
            try Task.checkCancellation(); try session.write(resampler.finish())
            let result = try session.finish()
            await update(RadioUpdate(text: result.text, frame: frame, progress: 1, source: url.lastPathComponent,
                detail: "\(Int(reader.sampleRate)) Hz · " + result.status, finished: true, channelCount: reader.channelCount, multimonRecords: result.records))
        } onCancel: { session.cancel() }
    }
    private func decodeMultimonLive(ring: AudioSampleRing, sampleRate: Double, mode: RadioMode, settings: DecoderSettings,
                                   source: String, update: @Sendable (RadioUpdate) async -> Void) async throws {
        try settings.validated(sampleRate: sampleRate, mode: mode)
        var session = try MultimonProcess(mode: mode, settings: settings)
        var resampler = try StreamingAudioResampler(sampleRate: sampleRate, outputRate: 22050)
        var retained: [MultimonRecord] = [], storage = [Float](repeating: 0, count: 8192)
        let spectrum = SpectrumAnalyzer()
        var lastUpdate = 0.0, previousDrop: UInt64 = 0
        var lastPublishedTotal = 0
        defer { session.cancel() }
        while !Task.isCancelled {
            let count = ring.read(into: &storage)
            let samples = Array(storage.prefix(count))
            if count > 0 {
                if ring.dropped != previousDrop {
                    retained = Array((retained + session.snapshot.records).suffix(100)); session.cancel()
                    session = try MultimonProcess(mode: mode, settings: settings)
                    resampler = try StreamingAudioResampler(sampleRate: sampleRate, outputRate: 22050); previousDrop = ring.dropped
                }
                let active = session
                try await withTaskCancellationHandler { try active.write(resampler.process(samples)) } onCancel: { active.cancel() }
            }
            // stdout is asynchronous: a decoded event can arrive after the
            // last audio block. Publish it even while the ring is empty.
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastUpdate >= 0.1 {
                let result = session.snapshot
                if count > 0 || result.total != lastPublishedTotal {
                    let records = Array((retained + result.records).suffix(200))
                    await update(RadioUpdate(text: records.map(\.monitorLine).joined(separator: "\n"), frame: count > 0 ? spectrum.analyze(samples, sampleRate: sampleRate) : nil, progress: 0,
                        source: source, detail: "\(Int(sampleRate)) Hz · \(settings.audioChannel.label) · " + result.status, dropped: ring.dropped,
                        samplesReceived: ring.written + ring.dropped, multimonRecords: records))
                    lastPublishedTotal = result.total
                }
                lastUpdate = now
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
