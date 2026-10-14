import AVFoundation
import Foundation
import RadioCore

// Explicit launch flag only. All allocation/disk I/O runs on RadioWorker,
// never the realtime tap. The file closes after at most 90 s of mono PCM.
final class AudioDiagnosticRecorder {
    private var file: AVAudioFile?
    private let buffer: AVAudioPCMBuffer
    private var remaining: Int64
    private init(url: URL, rate: Double) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.buffer = buffer; remaining = Int64(rate * 90)
    }
    static func requested(rate: Double, mode: RadioMode) throws -> AudioDiagnosticRecorder? {
        let args = ProcessInfo.processInfo.arguments
        guard mode == .sstv, args.contains("--sstv-microphone-test"),
              let index = args.firstIndex(of: "--diagnostic-wav"), index + 1 < args.count else { return nil }
        return try AudioDiagnosticRecorder(url: URL(fileURLWithPath: args[index + 1]), rate: rate)
    }
    func write(_ samples: [Float]) throws {
        guard let file, remaining > 0 else { return }
        let count = min(samples.count, Int(buffer.frameCapacity), Int(remaining))
        buffer.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { buffer.floatChannelData![0].update(from: base, count: count) }
        }
        try file.write(from: buffer); remaining -= Int64(count)
        if remaining == 0 { self.file = nil }
    }
}
