import AVFoundation
import Foundation
import RadioCore

/// Owns output-only audio. All player operations use one queue; the frame budget
/// is reserved before dispatch so even pending work cannot grow without bound.
final class DMRVoiceMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "RadioWorkbench.DMRVoiceMonitor")
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var active = true
    private var queuedFrames = 0
    private var droppedFrames: UInt64 = 0
    private var started = false
    private var finishing = false
    init(offline: Bool = false) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 2) else { throw RadioError.invalidAudio }
        self.format = format
        try queue.sync {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            if offline { try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 2048) }
            engine.prepare(); try engine.start()
        }
    }
    func enqueue(_ chunk: DigitalVoicePCMChunk) {
        guard chunk.channels == 2, chunk.sampleRate == 8000, chunk.frameCount > 0, chunk.frameCount <= 2048 else { return }
        lock.lock()
        guard active, !finishing else { lock.unlock(); return }
        guard queuedFrames + chunk.frameCount <= 16000 else { droppedFrames += UInt64(chunk.frameCount); lock.unlock(); return }
        queuedFrames += chunk.frameCount; lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let active = self.active; self.lock.unlock()
            guard active, let buffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: AVAudioFrameCount(chunk.frameCount)), let data = buffer.floatChannelData else {
                self.release(chunk.frameCount); return
            }
            buffer.frameLength = AVAudioFrameCount(chunk.frameCount)
            for i in 0..<chunk.frameCount { data[0][i] = chunk.samples[i * 2]; data[1][i] = chunk.samples[i * 2 + 1] }
            self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in self?.release(chunk.frameCount) }
            if !self.started { self.player.play(); self.started = true }
        }
    }
    private func release(_ frames: Int) {
        lock.lock(); queuedFrames = max(0, queuedFrames - frames); let end = finishing && queuedFrames == 0; lock.unlock()
        if end { stopAfterPlayback() }
    }
    func finish() {
        lock.lock(); finishing = true; let end = queuedFrames == 0; lock.unlock()
        if end { stopAfterPlayback() }
    }
    private func stopAfterPlayback() {
        queue.async { [weak self] in
            guard let self else { return }
            self.player.stop(); self.engine.stop(); self.started = false
        }
    }
    var snapshot: (queued: Int, dropped: UInt64) { lock.lock(); defer { lock.unlock() }; return (queuedFrames, droppedFrames) }
    func stop() {
        lock.lock(); active = false; lock.unlock()
        queue.sync { player.stop(); engine.stop(); started = false }
        lock.lock(); queuedFrames = 0; lock.unlock()
    }
    /// Offline rendering exercises the actual output graph without speakers or input capture.
    func renderOffline(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        try queue.sync {
            guard frames <= 2048, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw RadioError.invalidAudio }
            let result = try engine.renderOffline(frames, to: buffer)
            guard result == .success else { throw RadioError.invalidAudio }
            return buffer
        }
    }
    deinit { player.stop(); engine.stop() }
}
