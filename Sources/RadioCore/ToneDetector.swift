import Foundation

// Non-overlapping short Goertzel windows. Input amplitude is normalized PCM.
struct ToneDetector {
    let coefficient: Double
    let length: Int
    var s1 = 0.0, s2 = 0.0
    var count = 0
    init(frequency: Double, sampleRate: Double, duration: Double) {
        coefficient = 2 * cos(2 * .pi * frequency / sampleRate)
        length = max(16, Int(sampleRate * duration))
    }
    mutating func push(_ value: Float) -> Double? {
        let next = Double(value) + coefficient * s1 - s2
        s2 = s1; s1 = next; count += 1
        guard count == length else { return nil }
        let power = max(0, s1 * s1 + s2 * s2 - coefficient * s1 * s2)
        let amplitude = 2 * sqrt(power) / Double(length)
        count = 0; s1 = 0; s2 = 0
        return amplitude
    }
}
