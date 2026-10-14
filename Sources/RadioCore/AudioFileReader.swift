import AVFoundation
import Accelerate
import Foundation

// Read and downmix bounded PCM chunks on the caller's worker, preserving rate.
public final class AudioFileReader {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let channel: AudioChannelSelection
    public var sampleRate: Double { file.processingFormat.sampleRate }
    public var channelCount: Int { Int(file.processingFormat.channelCount) }
    public var duration: Double { Double(file.length) / sampleRate }
    public var progress: Double { file.length == 0 ? 1 : Double(file.framePosition) / Double(file.length) }
    public init(url: URL, channel: AudioChannelSelection = .mix) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0, file.processingFormat.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else {
            throw RadioError.invalidAudio
        }
        self.buffer = buffer
        try channel.validate(channelCount: Int(file.processingFormat.channelCount))
        self.channel = channel
    }
    public func next() throws -> [Float]? {
        guard file.framePosition < file.length else { return nil }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw RadioError.invalidAudio }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        var mono: [Float]
        if case .channel(let index) = channel {
            mono = Array(UnsafeBufferPointer(start: channels[index], count: count))
        } else {
            mono = [Float](repeating: 0, count: count)
            for index in 0..<channelCount {
                vDSP_vadd(mono, 1, channels[index], 1, &mono, 1, vDSP_Length(count))
            }
            var scale = Float(1) / Float(channelCount)
            vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(count))
        }
        guard mono.allSatisfy(\.isFinite) else { throw RadioError.invalidAudio }
        return mono
    }
}
