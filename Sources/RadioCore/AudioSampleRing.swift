import AVFoundation
import AudioRing
import AudioToolbox

// Exactly one tap produces and one worker consumes. The C indices are atomic;
// the callback retains this owner until the engine releases its tap.
public final class AudioSampleRing: @unchecked Sendable {
    private let pointer: OpaquePointer
    private let channel: AudioChannelSelection

    public init(channel: AudioChannelSelection = .mix, capacity: Int = 131072) throws {
        guard capacity > 0, let pointer = radio_ring_create(capacity) else { throw RadioError.invalidAudio }
        self.pointer = pointer; self.channel = channel
    }
    deinit { radio_ring_destroy(pointer) }

    public func write(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved else { return }
        write(buffer.audioBufferList, frames: Int(buffer.frameLength), channels: Int(buffer.format.channelCount))
    }

    @available(macOS 27.0, *)
    public func write(_ buffer: AVReadOnlyAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved else { return }
        buffer.withUnsafeAudioBufferList {
            write($0, frames: buffer.frameLength, channels: Int(buffer.format.channelCount))
        }
    }

    private func write(_ list: UnsafePointer<AudioBufferList>, frames: Int, channels: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard frames > 0, (1...32).contains(channels), buffers.count == channels else { return }
        for buffer in buffers {
            guard buffer.mNumberChannels == 1, buffer.mData != nil,
                  Int(buffer.mDataByteSize) >= frames * MemoryLayout<Float>.size else { return }
        }
        if case .channel(let index) = channel {
            guard index >= 0, index < channels, let data = buffers[index].mData else { return }
            _ = radio_ring_write_mono(pointer, data.assumingMemoryBound(to: Float.self), nil, frames)
        } else {
            // Bounded pointer list on the stack; no PCM copy/allocation in the tap.
            withUnsafeTemporaryAllocation(of: UnsafePointer<Float>?.self, capacity: channels) { pointers in
                for index in 0..<channels {
                    pointers[index] = UnsafePointer(buffers[index].mData!.assumingMemoryBound(to: Float.self))
                }
                _ = radio_ring_write(pointer, pointers.baseAddress, channels, frames)
            }
        }
    }

    public func read(into buffer: inout [Float]) -> Int {
        buffer.withUnsafeMutableBufferPointer { radio_ring_read(pointer, $0.baseAddress, $0.count) }
    }
    /// A network/file producer can use the same bounded single-producer ring.
    /// Never call this concurrently with an audio tap writing this instance.
    public func writeMono(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { buffer in
            _ = radio_ring_write_mono(pointer, buffer.baseAddress, nil, buffer.count)
        }
    }
    public var dropped: UInt64 { radio_ring_dropped(pointer) }
    public var written: UInt64 { radio_ring_written(pointer) }
    /// The producer calls this after its final write; buffered samples remain
    /// readable. Once empty, the consumer can flush its decoder normally.
    public func finish() { radio_ring_finish(pointer) }
    public var isFinished: Bool { radio_ring_finished(pointer) != 0 }
    public var isDrained: Bool { radio_ring_drained(pointer) != 0 }
}
