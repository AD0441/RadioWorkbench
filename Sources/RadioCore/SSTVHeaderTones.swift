import Foundation

// Coherent 8 ms Goertzel windows, updated every 2 ms. This isolates VIS tones
// from microphone noise without relying on noisy one-sample phase derivatives.
struct SSTVHeaderTones {
    private var samples: [Double]
    private let coefficients: [Double]
    private let tones = [1100.0, 1200, 1300, 1900, 2100]
    private let rate: Double, hop: Int
    private var position = 0, count = 0, tick = 0
    init(sampleRate: Double, center: Double) {
        rate = sampleRate; hop = max(1, Int((sampleRate * 0.002).rounded()))
        samples = Array(repeating: 0, count: max(16, Int((sampleRate * 0.008).rounded())))
        coefficients = [1100.0, 1200, 1300, 1900, 2100].map { 2 * cos(2 * .pi * ($0 + center - 1900) / sampleRate) }
    }
    mutating func push(_ sample: Float) -> (frequency: Double, amplitude: Double, time: Double)? {
        samples[position] = Double(sample); position += 1; if position == samples.count { position = 0 }
        count += 1; tick += 1
        guard count >= samples.count, tick >= hop else { return nil }; tick = 0
        var best = 0.0, bestTone = 0.0, total = 0.0
        for x in samples { total += x * x }
        for index in tones.indices {
            var s1 = 0.0, s2 = 0.0, cursor = position
            let coefficient = coefficients[index]
            for _ in samples.indices {
                let next = samples[cursor] + coefficient * s1 - s2
                s2 = s1; s1 = next
                cursor += 1; if cursor == samples.count { cursor = 0 }
            }
            let power = max(0, s1 * s1 + s2 * s2 - coefficient * s1 * s2)
            if power > best { best = power; bestTone = tones[index] }
        }
        let purity = total > 0 ? 2 * best / (Double(samples.count) * total) : 0
        return (purity >= 0.12 ? bestTone : 0, purity >= 0.12 ? 2 * sqrt(best) / Double(samples.count) : 0,
                (Double(count - 1) - Double(samples.count - 1) / 2) / rate)
    }
}
