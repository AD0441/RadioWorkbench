import Foundation

// A short-lag complex discriminator avoids averaging wrapped, one-sample
// phase spikes. Bounded history and output at <= 12 kHz keep 96 kHz input cheap.
struct SSTVVideoDemodulator {
    private var analytic: AnalyticAudio
    private var real: [Double], imaginary: [Double]
    private let lag: Int, hop: Int, rate: Double, center: Double
    private let rotationCos: Double, rotationSin: Double
    private var position = 0, count = 0, tick = 0
    private var crossSum = 0.0, dotSum = 0.0, energy = 0.0
    private var frequencySum = 0.0
    private let reduction: SSTVNoiseReduction
    init(sampleRate: Double, center: Double, reduction: SSTVNoiseReduction) {
        rate = sampleRate; self.center = center; self.reduction = reduction
        analytic = AnalyticAudio(sampleRate: sampleRate)
        lag = max(1, Int((sampleRate * (reduction == .strong ? 0.00020 : 0.00012)).rounded()))
        hop = max(1, Int((sampleRate / 12000).rounded(.up)))
        real = Array(repeating: 0, count: lag); imaginary = real
        let angle = 2 * Double.pi * center * Double(lag) / sampleRate
        rotationCos = cos(angle); rotationSin = sin(angle)
    }
    mutating func push(_ sample: Float) -> (frequency: Double, amplitude: Double, time: Double)? {
        guard let value = analytic.push(sample) else { return nil }
        let oldI = real[position], oldQ = imaginary[position]
        real[position] = value.real; imaginary[position] = value.imaginary
        position += 1; if position == lag { position = 0 }; count += 1
        guard count > lag else { return nil }
        let cross = oldI * value.imaginary - oldQ * value.real
        let dot = oldI * value.real + oldQ * value.imaginary
        crossSum += cross; dotSum += dot; energy += value.amplitude * value.amplitude; frequencySum += value.frequency; tick += 1
        guard tick >= hop else { return nil }
        let rotatedCross = crossSum * rotationCos - dotSum * rotationSin
        let rotatedDot = dotSum * rotationCos + crossSum * rotationSin
        let frequency = reduction == .off ? frequencySum / Double(tick) : center + atan2(rotatedCross, rotatedDot) * rate / (2 * .pi * Double(lag))
        let amplitude = sqrt(energy / Double(tick))
        let time = value.time - Double((reduction == .off ? 0 : lag) + tick - 1) / (2 * rate)
        tick = 0; crossSum = 0; dotSum = 0; energy = 0; frequencySum = 0
        return (frequency, amplitude, time)
    }
}
