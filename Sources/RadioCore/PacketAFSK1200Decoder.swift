import Foundation

// Bell 202 tone correlators with a one-symbol sliding integration window.
// Buffers and oscillators are created once; there is no per-sample allocation.
private struct PacketToneCorrelator {
    private var historyI: [Double], historyQ: [Double]
    private var sumI = 0.0, sumQ = 0.0, index = 0
    private var oscillatorI = 1.0, oscillatorQ = 0.0
    private let stepI: Double, stepQ: Double
    private var renormalize = 0
    let length: Int

    init(frequency: Double, sampleRate: Double, length: Int) {
        self.length = length
        historyI = [Double](repeating: 0, count: length)
        historyQ = [Double](repeating: 0, count: length)
        stepI = cos(2 * .pi * frequency / sampleRate)
        stepQ = sin(2 * .pi * frequency / sampleRate)
    }

    mutating func push(_ sample: Double) -> Double {
        let i = sample * oscillatorI, q = sample * oscillatorQ
        sumI += i - historyI[index]; sumQ += q - historyQ[index]
        historyI[index] = i; historyQ[index] = q
        index = (index + 1) % length
        let nextI = oscillatorI * stepI - oscillatorQ * stepQ
        oscillatorQ = oscillatorQ * stepI + oscillatorI * stepQ
        oscillatorI = nextI
        renormalize += 1
        if renormalize == 4096 {
            let scale = 1 / hypot(oscillatorI, oscillatorQ)
            oscillatorI *= scale; oscillatorQ *= scale; renormalize = 0
        }
        return sumI * sumI + sumQ * sumQ
    }
}

final class PacketAFSK1200Decoder {
    private var mark: PacketToneCorrelator, space: PacketToneCorrelator
    private let receiver = PacketHDLCReceiver()
    private let period: Double, amplitudeSquared: Double
    private var sampleIndex = 0.0, nextCenter: Double?
    private var lastTransitionTone: Bool?, previousSymbolTone: Bool?
    private var quietSamples = 0
    private let quietLimit: Int
    private var samplesSeen = 0
    private var recentAmplitude = 0.0
    private let amplitudeSmoothing: Double

    init(sampleRate: Double, settings: DecoderSettings) {
        period = sampleRate / 1200
        let length = max(4, Int(period.rounded()))
        // Center 1700 Hz => mark 1200 / space 2200. A shifted recording can be
        // recentered by the ordinary frequency control without changing baud.
        mark = PacketToneCorrelator(frequency: settings.frequency - 500, sampleRate: sampleRate, length: length)
        space = PacketToneCorrelator(frequency: settings.frequency + 500, sampleRate: sampleRate, length: length)
        amplitudeSquared = settings.threshold * settings.threshold / 2
        quietLimit = max(1, Int(sampleRate * 0.020))
        amplitudeSmoothing = 1 - exp(-1 / (sampleRate * 0.001))
    }

    func process(_ samples: [Float]) {
        for value in samples {
            let sample = value.isFinite ? Double(value) : 0
            let markPower = mark.push(sample), spacePower = space.push(sample)
            recentAmplitude += amplitudeSmoothing * (sample * sample - recentAmplitude)
            samplesSeen += 1; sampleIndex += 1
            guard samplesSeen >= mark.length else { continue }
            if recentAmplitude < amplitudeSquared {
                quietSamples += 1
                if quietSamples == quietLimit {
                    receiver.loseSignal(); nextCenter = nil
                    lastTransitionTone = nil; previousSymbolTone = nil
                }
                continue
            }
            quietSamples = 0
            let tone = markPower >= spacePower
            if nextCenter == nil { nextCenter = sampleIndex + period / 2 }
            if let lastTransitionTone, lastTransitionTone != tone, let scheduled = nextCenter {
                var error = (sampleIndex + period / 2 - scheduled).truncatingRemainder(dividingBy: period)
                if error > period / 2 { error -= period }
                if error < -period / 2 { error += period }
                nextCenter = scheduled + 0.35 * error
            }
            lastTransitionTone = tone
            if let scheduled = nextCenter, sampleIndex >= scheduled {
                if let previousSymbolTone { receiver.push(bit: previousSymbolTone == tone) }
                previousSymbolTone = tone
                nextCenter = scheduled + period
            }
        }
    }

    var text: String { receiver.text }
    var status: String { receiver.status }
    var acceptedFrames: Int { receiver.accepted }
    var rejectedCRC: Int { receiver.rejectedCRC }
}
