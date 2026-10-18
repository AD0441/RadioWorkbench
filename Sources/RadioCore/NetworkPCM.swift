import Foundation

public enum NetworkPCMSampleFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case signed16LittleEndian = "s16le", float32LittleEndian = "float32le"
    public var id: String { rawValue }
    public var title: String { self == .signed16LittleEndian ? "PCM 16 bits · little-endian" : "PCM Float32 · little-endian" }
    public var bytesPerSample: Int { self == .signed16LittleEndian ? 2 : 4 }
}

public struct NetworkPCMConfiguration: Codable, Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var sampleRate: Double
    public var channels: Int
    public var format: NetworkPCMSampleFormat
    public init(host: String = "127.0.0.1", port: UInt16 = 7355, sampleRate: Double = 48000,
                channels: Int = 1, format: NetworkPCMSampleFormat = .signed16LittleEndian) {
        self.host = host; self.port = port; self.sampleRate = sampleRate; self.channels = channels; self.format = format
    }
    /// Literal loopback addresses only: no DNS names, remote hosts or discovery.
    public var isValid: Bool {
        (host == "127.0.0.1" || host == "::1") && port > 0 && sampleRate.isFinite
            && (4000...384000).contains(sampleRate) && (1...32).contains(channels)
    }
    public func validated() throws -> Self {
        guard isValid else { throw NetworkPCMError.invalidConfiguration }
        return self
    }
    public var bytesPerFrame: Int { channels * format.bytesPerSample }
}

public enum NetworkPCMError: LocalizedError, Equatable {
    case invalidConfiguration, oversizedChunk, nonFiniteSample, truncatedFrame(Int), streamClosed
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Usa 127.0.0.1 o ::1, un puerto válido, 4–384 kHz y 1–32 canales. El formato debe coincidir con el emisor."
        case .oversizedChunk: "El bloque de audio TCP supera el tamaño admitido."
        case .nonFiniteSample: "El audio Float32 contiene valores no válidos. Revisa el formato elegido en ambos programas."
        case .truncatedFrame(let missing): "La conexión terminó a mitad de una muestra o de sus canales; faltaban \(missing) bytes para completar el bloque PCM."
        case .streamClosed: "Esta sesión de audio TCP ya terminó. Inicia otra conexión para continuar."
        }
    }
}

/// Incremental raw PCM parser. Sample/frame boundaries may span TCP packets.
/// One serial producer owns this value and writes the returned mono samples.
public struct NetworkPCMParser: Sendable {
    public static let maximumChunkBytes = 65536
    public let configuration: NetworkPCMConfiguration
    public let channel: AudioChannelSelection
    public private(set) var bytesReceived: UInt64 = 0
    public private(set) var framesDecoded: UInt64 = 0
    public private(set) var clippedSamples: UInt64 = 0
    public var pendingByteCount: Int { pending.count }
    private var pending: [UInt8] = []
    private var terminal = false

    public init(configuration: NetworkPCMConfiguration, channel: AudioChannelSelection = .mix) throws {
        self.configuration = try configuration.validated(); self.channel = channel
        try channel.validate(channelCount: configuration.channels)
        pending.reserveCapacity(configuration.bytesPerFrame - 1)
    }
    public mutating func append(_ data: Data) throws -> [Float] {
        guard !terminal else { throw NetworkPCMError.streamClosed }
        guard data.count <= Self.maximumChunkBytes else { terminal = true; throw NetworkPCMError.oversizedChunk }
        bytesReceived += UInt64(data.count)
        var bytes = pending; bytes.append(contentsOf: data)
        let stride = configuration.format.bytesPerSample, frameSize = configuration.bytesPerFrame
        let frames = bytes.count / frameSize
        var mono: [Float] = []; mono.reserveCapacity(frames)
        var clipped: UInt64 = 0
        for frame in 0..<frames {
            var sum: Float = 0, chosen: Float = 0
            for sourceChannel in 0..<configuration.channels {
                let offset = frame * frameSize + sourceChannel * stride
                let value: Float
                switch configuration.format {
                case .signed16LittleEndian:
                    let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
                    value = Float(Int16(bitPattern: bits)) / 32768
                case .float32LittleEndian:
                    let bits = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                        | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
                    let sample = Float(bitPattern: bits)
                    guard sample.isFinite else { terminal = true; throw NetworkPCMError.nonFiniteSample }
                    if abs(sample) > 1 { clipped += 1 }
                    value = max(-1, min(1, sample))
                }
                sum += value
                if case .channel(let selected) = channel, selected == sourceChannel { chosen = value }
            }
            if case .mix = channel { mono.append(sum / Float(configuration.channels)) }
            else { mono.append(chosen) }
        }
        pending = Array(bytes.dropFirst(frames * frameSize))
        framesDecoded += UInt64(frames); clippedSamples += clipped
        return mono
    }
    public mutating func finish() throws {
        guard !terminal else { throw NetworkPCMError.streamClosed }
        terminal = true
        guard pending.isEmpty else { throw NetworkPCMError.truncatedFrame(configuration.bytesPerFrame - pending.count) }
    }
}
