import Accelerate
import Foundation

// Only measures a stable VIS leader. FFT interpolation avoids the frequency
// bias of a phase discriminator when microphone noise is comparable to tone.
final class SSTVCarrierEstimator {
    private let rate: Double, center: Double, size: Int, setup: vDSP_DFT_Setup
    private var real: [Float], imaginary: [Float], outReal: [Float], outImaginary: [Float], window: [Float]
    private var count = 0
    init?(sampleRate: Double, center: Double) {
        rate = sampleRate; self.center = center
        var n = 512; while Double(n) < sampleRate * 0.064 { n *= 2 }; size = n
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else { return nil }; self.setup = setup
        real = Array(repeating: 0, count: n); imaginary = real; outReal = real; outImaginary = real; window = real
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_DFT_DestroySetup(setup) }
    func push(_ sample: Float, measuring: Bool, threshold: Double) -> Double? {
        guard measuring else { count = 0; return nil }
        real[count] = sample * window[count]; count += 1
        guard count == size else { return nil }; count = 0
        vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
        let lower = max(1, Int((center - 160) * Double(size) / rate))
        let upper = min(size / 2 - 2, Int((center + 160) * Double(size) / rate))
        guard upper > lower else { return nil }
        func power(_ bin: Int) -> Double { Double(outReal[bin]) * Double(outReal[bin]) + Double(outImaginary[bin]) * Double(outImaginary[bin]) }
        var peak = lower
        for bin in lower...upper where power(bin) > power(peak) { peak = bin }
        let energy = real.reduce(0.0) { $0 + Double($1) * Double($1) }
        let peakPower = power(peak)
        guard 2 * peakPower / max(1e-30, Double(size) * energy) > 0.35,
              4 * sqrt(peakPower) / Double(size) >= threshold / 2 else { return nil }
        let a = log(max(1e-30, power(peak - 1))), b = log(max(1e-30, peakPower)), c = log(max(1e-30, power(peak + 1)))
        let divisor = 2 * (a - 2 * b + c)
        let fraction = abs(divisor) > 1e-12 ? min(0.5, max(-0.5, (a - c) / divisor)) : 0
        return (Double(peak) + fraction) * rate / Double(size)
    }
}
