import Foundation

// Reject microphone rumble and speaker harmonics before phase demodulation.
// RBJ/W3C bilinear biquads: 4th-order Butterworth HP and LP.
// https://www.w3.org/TR/audio-eq-cookbook/
struct SSTVAudioBand {
    private var highA: Biquad
    private var highB: Biquad
    private var lowA: Biquad
    private var lowB: Biquad
    init(sampleRate: Double, center: Double) {
        let offset = center - 1900
        let lowCut = max(100, 900 + offset)
        let highCut = min(sampleRate * 0.45, 3200 + offset)
        highA = Biquad(rate: sampleRate, frequency: lowCut, q: 0.541196100146197, highPass: true)
        highB = Biquad(rate: sampleRate, frequency: lowCut, q: 1.306562964876377, highPass: true)
        lowA = Biquad(rate: sampleRate, frequency: highCut, q: 0.541196100146197, highPass: false)
        lowB = Biquad(rate: sampleRate, frequency: highCut, q: 1.306562964876377, highPass: false)
    }
    mutating func push(_ value: Float) -> Float {
        Float(lowB.push(lowA.push(highB.push(highA.push(Double(value))))))
    }
    private struct Biquad {
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1 = 0.0, z2 = 0.0
        init(rate: Double, frequency: Double, q: Double, highPass: Bool) {
            let omega = 2 * Double.pi * frequency / rate
            let cosine = cos(omega), alpha = sin(omega) / (2 * q), a0 = 1 + alpha
            let numerator = highPass ? 1 + cosine : 1 - cosine
            b0 = numerator / (2 * a0); b2 = b0
            b1 = (highPass ? -numerator : numerator) / a0
            a1 = -2 * cosine / a0; a2 = (1 - alpha) / a0
        }
        mutating func push(_ input: Double) -> Double {
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            return output
        }
    }
}
