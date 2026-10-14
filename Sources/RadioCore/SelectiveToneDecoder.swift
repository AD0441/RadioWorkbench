import Foundation

// Frequency facts verified against SDRangel's CTCSS frequency list. The DSP
// and state machine below are independent implementations, not copied code.
enum CTCSSFrequency {
    static let all: [Double] = [
        67.0,69.3,71.9,74.4,77.0,79.7,82.5,85.4,88.5,91.5,
        94.8,97.4,100.0,103.5,107.2,110.9,114.8,118.8,123.0,127.3,
        131.8,136.5,141.3,146.2,150.0,151.4,156.7,159.8,162.2,165.5,
        167.9,171.3,173.8,177.3,179.9,183.5,186.2,189.9,192.8,196.6,
        199.5,203.5,206.5,210.7,218.1,225.7,229.1,233.6,241.8,250.3,254.1
    ]
}

private struct SelectiveLowPass {
    let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var z1 = 0.0, z2 = 0.0
    init(sampleRate: Double, q: Double) {
        let omega = 2 * Double.pi * 300 / sampleRate
        let c = cos(omega), alpha = sin(omega) / (2 * q), scale = 1 / (1 + alpha)
        b0 = (1 - c) / 2 * scale; b1 = (1 - c) * scale; b2 = b0
        a1 = -2 * c * scale; a2 = (1 - alpha) * scale
    }
    mutating func push(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }
}

// Passive CTCSS monitor only; DCS and five-tone sequences are separate modes.
final class SelectiveToneDecoder {
    private let rate: Double, minimumAmplitude: Double, highPassPole: Double
    private var lowPass: [SelectiveLowPass]
    private var previousInput = 0.0, highPassOutput = 0.0, previousFiltered = 0.0
    private var sourcePosition = 0.0, nextResamplePosition = 0.0
    private let resampleStep: Double
    private static let analysisRate = 1024.0
    private static let windowLength = 2048, hop = 256
    private var history = [Double](repeating: 0, count: windowLength)
    private var write = 0, analysisSamples = 0
    private let window: [Double], windowSum: Double, windowSquareSum: Double, coefficients: [Double]
    private var weighted = [Double](repeating: 0, count: windowLength)
    private var candidate: Int?, candidateCount = 0, misses = 0
    private var lockedIndex: Int?, lockedAt = 0.0
    private(set) var confidence = 0.0
    private(set) var text = ""
    private(set) var detections = 0

    init(sampleRate: Double, settings: DecoderSettings) {
        rate = sampleRate; minimumAmplitude = settings.threshold
        highPassPole = exp(-2 * .pi * 25 / sampleRate)
        resampleStep = sampleRate / Self.analysisRate
        // Eighth-order Butterworth anti-alias filter. Preserve subaudio while
        // rejecting voice and content that would alias during decimation.
        lowPass = [0.509795579,0.601344887,0.899976223,2.562915448].map { SelectiveLowPass(sampleRate: sampleRate, q: $0) }
        window = (0..<Self.windowLength).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(Self.windowLength - 1)) }
        windowSum = window.reduce(0,+)
        windowSquareSum = window.reduce(0) { $0 + $1 * $1 }
        coefficients = CTCSSFrequency.all.map { 2 * cos(2 * .pi * $0 / Self.analysisRate) }
    }

    func process(_ samples: [Float]) {
        for value in samples {
            let sample = value.isFinite ? Double(value) : 0
            highPassOutput = highPassPole * (highPassOutput + sample - previousInput)
            previousInput = sample
            var filtered = highPassOutput
            for index in lowPass.indices { filtered = lowPass[index].push(filtered) }
            // Input is filtered before fractional decimation. Positions use
            // the source clock; timer/UI cadence cannot affect the detector.
            if sourcePosition >= nextResamplePosition {
                let fraction = min(1, max(0, nextResamplePosition - (sourcePosition - 1)))
                pushAnalysis(previousFiltered + fraction * (filtered - previousFiltered))
                nextResamplePosition += resampleStep
            }
            previousFiltered = filtered; sourcePosition += 1
        }
    }

    private func pushAnalysis(_ sample: Double) {
        history[write] = sample; write = (write + 1) % Self.windowLength
        analysisSamples += 1
        guard analysisSamples >= Self.windowLength,
              (analysisSamples - Self.windowLength) % Self.hop == 0 else { return }
        analyze()
    }

    private func analyze() {
        var energy = 0.0
        for index in 0..<Self.windowLength {
            let sample = history[(write + index) % Self.windowLength] * window[index]
            weighted[index] = sample; energy += sample * sample
        }
        let time = Double(analysisSamples) / Self.analysisRate
        guard energy > 1e-12 else { update(nil, quality: 0, time: time); return }
        var best = 0.0, second = 0.0, bestIndex = 0
        for index in coefficients.indices {
            var previous = 0.0, beforePrevious = 0.0
            let coefficient = coefficients[index]
            for sample in weighted {
                let next = sample + coefficient * previous - beforePrevious
                beforePrevious = previous; previous = next
            }
            let power = max(0, previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
            if power > best { second = best; best = power; bestIndex = index }
            else if power > second { second = power }
        }
        let amplitude = 2 * sqrt(best) / windowSum
        // A coherent sine explains essentially all Hann-weighted energy.
        // Broad noise, a changing pitch or equal competing tones do not.
        let purity = min(1, 2 * best * windowSquareSum / (windowSum * windowSum * energy))
        let separation = best > 0 ? 1 - second / best : 0
        let valid = amplitude >= minimumAmplitude && purity >= 0.62 && separation >= 0.65
        update(valid ? bestIndex : nil, quality: valid ? purity * separation : 0, time: time)
    }

    private func update(_ index: Int?, quality: Double, time: Double) {
        if index == lockedIndex, let index {
            confidence = quality; misses = 0; candidate = index; candidateCount = 3
            return
        }
        if let index {
            if candidate == index { candidateCount += 1 }
            else { candidate = index; candidateCount = 1 }
            if candidateCount >= 3 {
                if lockedIndex != nil { release(at: time) }
                lockedIndex = index; lockedAt = time; confidence = quality
                misses = 0; detections += 1
                append(String(format: "CTCSS %.1f Hz · inicio confirmado %.2f s · confianza %.0f %%\n", CTCSSFrequency.all[index], time, quality * 100))
                return
            }
        } else { candidate = nil; candidateCount = 0 }
        if lockedIndex != nil {
            misses += 1
            if misses >= 2 { release(at: time) }
        }
    }

    private func release(at time: Double) {
        if let lockedIndex {
            append(String(format: "CTCSS %.1f Hz · fin confirmado %.2f s · duración confirmada %.2f s\n", CTCSSFrequency.all[lockedIndex], time, max(0, time - lockedAt)))
        }
        lockedIndex = nil; confidence = 0; misses = 0
    }

    private func append(_ line: String) {
        text.append(line)
        if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
    }

    var frequency: Double? { lockedIndex.map { CTCSSFrequency.all[$0] } }
    var confirmedDuration: Double { lockedIndex == nil ? 0 : max(0, Double(analysisSamples) / Self.analysisRate - lockedAt) }
    var status: String {
        if let frequency {
            return String(format: "CTCSS %.1f Hz · confianza %.0f %% · confirmado %.2f s", frequency, confidence * 100, confirmedDuration)
        }
        return "Buscando CTCSS · 51 tonos · ventana 2 s · \(detections) detecciones confirmadas"
    }
}
