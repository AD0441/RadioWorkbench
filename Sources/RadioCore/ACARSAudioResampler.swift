import Foundation

// Streaming, normalized windowed-sinc FIR. The source clock crosses block
// boundaries unchanged; 128 phases bound fractional-position error.
public final class ACARSAudioResampler {
    private let step: Double
    private let radius: Int
    private let weights: [[Float]]
    private var buffer: [Float]
    private var firstIndex: Int
    private var inputCount = 0
    private var nextPosition = 0.0
    public init(sampleRate: Double) throws {
        guard sampleRate.isFinite, (8000...384000).contains(sampleRate) else { throw RadioError.invalidSettings }
        step = sampleRate / 12000
        radius = max(24, Int(24 * max(1, step)))
        firstIndex = -radius; buffer = [Float](repeating: 0, count: radius)
        let cutoff = 0.45 * min(1, 12000 / sampleRate)
        var bank: [[Float]] = []
        for phase in 0..<128 {
            let fraction = Double(phase) / 128
            var taps: [Float] = []
            for tap in (-radius+1)...radius {
                let delta = Double(tap) - fraction
                let sinc = abs(delta) < 1e-10 ? 2 * cutoff : sin(2 * .pi * cutoff * delta) / (.pi * delta)
                let window = 0.5 + 0.5 * cos(.pi * delta / Double(radius))
                taps.append(Float(sinc * window))
            }
            let sum = taps.reduce(0,+)
            bank.append(taps.map { $0 / sum })
        }
        weights = bank
    }
    public func process(_ samples: [Float]) -> [Float] {
        buffer.append(contentsOf: samples); inputCount += samples.count
        return produce(finishing: false)
    }
    public func finish() -> [Float] {
        buffer.append(contentsOf: repeatElement(0, count: radius + 1))
        return produce(finishing: true)
    }
    private func produce(finishing: Bool) -> [Float] {
        var output: [Float] = []; output.reserveCapacity(Int(Double(buffer.count) / step))
        while nextPosition < Double(inputCount) {
            let center = Int(nextPosition)
            if center + radius >= firstIndex + buffer.count { break }
            let phase = min(127, Int((nextPosition - Double(center)) * 128))
            let start = center - radius + 1 - firstIndex
            var value: Float = 0
            for tap in weights[phase].indices { value += buffer[start + tap] * weights[phase][tap] }
            output.append(value); nextPosition += step
        }
        if !finishing {
            let discard = max(0, min(buffer.count, Int(nextPosition) - radius - firstIndex))
            buffer.removeFirst(discard); firstIndex += discard
        }
        return output
    }
}
