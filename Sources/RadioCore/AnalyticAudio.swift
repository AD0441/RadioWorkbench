import Foundation

// Windowed Hilbert FIR: construct analytic audio without assuming RF modulation.
// Its causal delay is subtracted from timestamps used by the image decoders.
struct AnalyticAudio {
    private var history: [Double]
    private let taps: [(Int, Double)]
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
        history = Array(repeating: 0, count: tapLength)
        let center = (tapLength - 1) / 2
        taps = (0..<tapLength).compactMap { index in
            let n = index - center
            guard n != 0 && abs(n) % 2 == 1 else { return nil }
            let window = 0.54 - 0.46 * cos(2 * .pi * Double(index) / Double(tapLength - 1))
            return (index, 2 * window / (.pi * Double(n)))
        }
    }
    mutating func push(_ sample: Float) -> (frequency: Double, amplitude: Double, time: Double, real: Double, imaginary: Double)? {
        history[write] = Double(sample)
        var q = 0.0
        for (lag, coefficient) in taps {
            let index = write - lag
            q += history[index < 0 ? index + length : index] * coefficient
        }
        let index = write - delay
        let i = history[index < 0 ? index + length : index]
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
