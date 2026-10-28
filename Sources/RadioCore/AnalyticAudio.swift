import Foundation
import Accelerate

// Windowed Hilbert FIR: construct analytic audio without assuming RF modulation.
// Its causal delay is subtracted from timestamps used by the image decoders.
struct AnalyticAudio {
    private var history: [Double]
    private let coefficients: [Double]
    private let maximumLag: Int
    private let length: Int
    private let delay: Int
    private var write = 0, samples = 0
    private var previousI = 0.0, previousQ = 0.0
    private let rate: Double
    init(sampleRate: Double) {
        rate = sampleRate
        let tapLength = min(257, max(63, Int(sampleRate * 0.004) | 1))
        length = tapLength
        delay = (tapLength - 1) / 2
        // Mirroring the ring makes every nonzero FIR tap a strided contiguous
        // read, so Accelerate can vectorize it without a wrap branch per tap.
        history = Array(repeating: 0, count: tapLength * 2)
        let center = (tapLength - 1) / 2
        let taps: [(Int, Double)] = (0..<tapLength).compactMap { index in
            let n = index - center
            guard n != 0 && abs(n) % 2 == 1 else { return nil }
            let window = 0.54 - 0.46 * cos(2 * .pi * Double(index) / Double(tapLength - 1))
            return (index, 2 * window / (.pi * Double(n)))
        }
        maximumLag = taps.last!.0
        coefficients = taps.reversed().map(\.1)
    }
    mutating func push(_ sample: Float) -> (frequency: Double, amplitude: Double, time: Double, real: Double, imaginary: Double)? {
        let value = sample.isFinite ? Double(sample) : 0
        history[write] = value
        history[write + length] = value
        var q = 0.0
        history.withUnsafeBufferPointer { signal in
            coefficients.withUnsafeBufferPointer { taps in
                vDSP_dotprD(signal.baseAddress! + write + length - maximumLag, 2,
                            taps.baseAddress!, 1, &q, vDSP_Length(taps.count))
            }
        }
        let i = history[write + length - delay]
        write += 1; if write == length { write = 0 }
        samples += 1
        let cross = previousI * q - previousQ * i
        let dot = previousI * i + previousQ * q
        let frequency = atan2(cross, dot) * rate / (2 * .pi)
        previousI = i; previousQ = q
        guard samples >= length else { return nil }
        return (frequency, hypot(i, q), Double(samples - 1 - delay) / rate, i, q)
    }
}
