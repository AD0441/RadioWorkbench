import Foundation

public enum SignalReference: String, CaseIterable, Sendable, Identifiable {
    case cw, rtty, psk31
    public var id: String { rawValue }
    public var title: String { switch self { case .cw: "CW · 700 Hz · 20 WPM"; case .rtty: "RTTY ITA2 · 45,45 baud · 170 Hz"; case .psk31: "BPSK31 · 31,25 baud · 1500 Hz" } }
    public var mode: RadioMode { switch self { case .cw: .morse; case .rtty: .rtty; case .psk31: .psk31 } }
    public var fileName: String { switch self { case .cw: "morse_8000_mono_clean"; case .rtty: "rtty_8000_mono_clean"; case .psk31: "bpsk31_8000_mono_clean" } }
    public var expectedText: String { self == .psk31 ? "CQ test 123" : "CQ TEST 123" }
    public var explanation: String {
        switch self {
        case .cw: "Un tono que se interrumpe. El punto dura 60 ms a 20 WPM; la raya dura tres puntos. Los espacios también codifican información."
        case .rtty: "Dos tonos: 1415 y 1585 Hz alrededor de 1500 Hz. El desplazamiento es 170 Hz. ITA2 usa 5 bits y cambios de letras/cifras; LSB puede invertir la polaridad."
        case .psk31: "La información está en cambios de fase a 31,25 símbolos/s. El espectro es estrecho, pero una línea estrecha por sí sola no confirma PSK31."
        }
    }
    public var settings: DecoderSettings {
        var settings = DecoderSettings(); settings.frequency = self == .cw ? 700 : 1500
        settings.wordsPerMinute = 20; settings.baud = 45.45; settings.shift = 170
        return settings
    }
}
public struct SignalProbeResult: Sendable {
    public let bins: [Float]
    public let upperFrequency: Double
    public let sampleRate: Double
    public let channels: Int
    public let secondsAnalyzed: Double
    public let levelDB: Double
    public let clippedSamples: Int
}
public enum SignalProbe {
    /// Average spectral power of at most the first twelve seconds; bounded PCM
    /// storage and FFT work, no auto classification or decoder confidence claim.
    public static func analyze(url: URL, channel: AudioChannelSelection = .mix) throws -> SignalProbeResult {
        let reader = try AudioFileReader(url: url, channel: channel), analyzer = SpectrumAnalyzer()
        var powers: [Double] = [], blocks = 0, samplesRead = 0, sumSquares = 0.0, clipped = 0, upper = 0.0
        let maximum = Int(reader.sampleRate * 12)
        while let samples = try reader.next(), samplesRead < maximum {
            try Task.checkCancellation()
            let samples = Array(samples.prefix(maximum - samplesRead)), frame = analyzer.analyze(samples, sampleRate: reader.sampleRate)
            if powers.isEmpty { powers = [Double](repeating: 0, count: frame.bins.count) }
            for index in powers.indices { powers[index] += pow(10, Double(frame.bins[index]) / 10) }
            let q = frame.quality
            sumSquares += q.rms * q.rms * Double(q.sampleCount); clipped += q.clippedCount
            samplesRead += samples.count; blocks += 1; upper = frame.upperFrequency
        }
        guard blocks > 0, samplesRead > 0 else { throw RadioError.invalidAudio }
        return .init(bins: powers.map { Float(10 * log10(max(1e-10, $0 / Double(blocks)))) }, upperFrequency: upper,
                     sampleRate: reader.sampleRate, channels: reader.channelCount, secondsAnalyzed: Double(samplesRead) / reader.sampleRate,
                     levelDB: 10 * log10(max(1e-10, sumSquares / Double(samplesRead))), clippedSamples: clipped)
    }
}
