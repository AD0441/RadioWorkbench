import Accelerate
import Foundation

public struct SpectrumFrame: Sendable {
    public let bins: [Float]
    public let upperFrequency: Double
    public let levelDB: Double
    public let peakFrequency: Double
    public let clipped: Bool
}

public final class SpectrumAnalyzer {
    private let size = 2048
    private let setup: vDSP_DFT_Setup
    private var real = [Float](repeating: 0, count: 2048)
    private var imaginary = [Float](repeating: 0, count: 2048)
    private var outputReal = [Float](repeating: 0, count: 2048)
    private var outputImaginary = [Float](repeating: 0, count: 2048)
    private var window = [Float](repeating: 0, count: 2048)
    public init() {
        setup = vDSP_DFT_zop_CreateSetup(nil, 2048, .FORWARD)!
        vDSP_hann_window(&window, 2048, Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_DFT_DestroySetup(setup) }
    public func analyze(_ samples: [Float], sampleRate: Double) -> SpectrumFrame {
        let n = min(size, samples.count)
        var rms: Float = 0
        if !samples.isEmpty { vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count)) }
        real.withUnsafeMutableBufferPointer { dest in
            for i in 0..<size { dest[i] = i < n ? samples[samples.count - n + i] * window[i] : 0 }
        }
        vDSP_DFT_Execute(setup, real, imaginary, &outputReal, &outputImaginary)
        let binHz = sampleRate / Double(size)
        let count = min(size / 2, max(2, Int(6000 / binHz)))
        var bins = [Float](repeating: 0, count: count)
        var peak = 1
        for i in 1..<count {
            let magnitude = hypot(outputReal[i], outputImaginary[i]) * 4 / Float(size)
            bins[i] = 20 * log10(max(0.00001, magnitude))
            if bins[i] > bins[peak] { peak = i }
        }
        bins[0] = -100
        return SpectrumFrame(bins: bins, upperFrequency: Double(count) * binHz,
                             levelDB: 20 * log10(max(0.00001, Double(rms))),
                             peakFrequency: Double(peak) * binHz,
                             clipped: samples.contains { abs($0) >= 0.999 })
    }
}
