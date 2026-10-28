import Foundation

private struct DGPSLowPass {
    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var z1 = 0.0, z2 = 0.0
    init(rate: Double, cutoff: Double, q: Double) {
        let w = 2 * Double.pi * cutoff / rate, c = cos(w), alpha = sin(w) / (2 * q), scale = 1 / (1 + alpha)
        b0 = (1 - c) * 0.5 * scale; b1 = (1 - c) * scale; b2 = b0
        a1 = -2 * c * scale; a2 = (1 - alpha) * scale
    }
    mutating func push(_ value: Double) -> Double {
        let output = b0 * value + z1
        z1 = b1 * value - a1 * output + z2; z2 = b2 * value - a2 * output
        return output
    }
}

private struct DGPSSymbolClock {
    let bitRate: Int
    private let increment: Double, initialPhase: Double
    private var phase: Double, integral = 0.0
    private var firstPartial = true
    private var receiver = DGPSRTCMReceiver()

    init(bitRate: Int, rate: Double, offset: Double) {
        self.bitRate = bitRate; increment = Double(bitRate) / rate
        phase = offset; initialPhase = offset
    }
    mutating func reset() {
        phase = initialPhase; integral = 0; firstPartial = true; receiver.reset()
    }
    mutating func push(frequency: Double, time: Double) -> DGPSReception? {
        // Fractional integration preserves phase-bank spacing at rates such as 44.1 kHz.
        let remaining = 1 - phase, take = min(increment, remaining)
        integral += frequency * take; phase += increment
        guard phase >= 1 - 1e-10 else { return nil }
        let decision = integral >= 0
        phase -= 1
        let remainder = increment - take
        integral = frequency * remainder
        if firstPartial { firstPartial = false; return nil }
        return receiver.push(bit: decision, time: time, bitRate: bitRate)
    }
}

/// Streaming receiver for an MSK beacon translated to mono SSB audio.
/// ITU-R M.823-3 Annex1 §1.5–1.7: continuous MSB-first data and ±90° per bit,
/// hence tone offsets ±baud/4. This is NOT an FM discriminator input decoder.
///
/// The complex mixer and anti-alias filters run at the input rate. Phase detection
/// and the two eight-phase symbol banks run near 1600 samples/s, including 96 kHz
/// microphone input. All histories, text and completed frames are bounded.
final class DGPSDecoder {
    private let sampleRate: Double, decimation: Int, demodRate: Double, threshold: Double
    private let stepI: Double, stepQ: Double
    private var oscillatorI = 1.0, oscillatorQ = 0.0
    private var filtersI: [DGPSLowPass], filtersQ: [DGPSLowPass]
    private var previousI = 0.0, previousQ = 0.0, havePrevious = false
    private var inputSamples = 0, downsample = 0, quiet = 0
    private var clocks: [DGPSSymbolClock]
    private var recent: [(key: String, time: Double)] = []
    private(set) var receptions: [DGPSReception] = []
    private(set) var acceptedFrames = 0
    private(set) var text = ""

    init(sampleRate: Double, settings: DecoderSettings) {
        self.sampleRate = sampleRate
        decimation = max(1, Int(sampleRate / 1600))
        demodRate = sampleRate / Double(decimation)
        threshold = settings.threshold
        let angle = 2 * Double.pi * settings.frequency / sampleRate
        stepI = cos(angle); stepQ = sin(angle)
        // Fourth-order anti-alias filter rejects the negative-frequency mixer image.
        filtersI = [0.541196100146197, 1.306562964876377].map {
            DGPSLowPass(rate: sampleRate, cutoff: 260, q: $0)
        }
        filtersQ = filtersI
        let rates = settings.dgpsRate.bitRate.map { [$0] } ?? [100, 200]
        let clockRate = demodRate
        clocks = rates.flatMap { rate in
            (0..<8).map { DGPSSymbolClock(bitRate: rate, rate: clockRate, offset: Double($0) / 8) }
        }
    }

    func process(_ samples: [Float]) {
        for raw in samples {
            let sample = raw.isFinite ? Double(raw) : 0
            var i = sample * oscillatorI, q = -sample * oscillatorQ
            let nextI = oscillatorI * stepI - oscillatorQ * stepQ
            oscillatorQ = oscillatorQ * stepI + oscillatorI * stepQ; oscillatorI = nextI
            inputSamples += 1
            if inputSamples & 8191 == 0 {
                let gain = 1 / hypot(oscillatorI, oscillatorQ)
                oscillatorI *= gain; oscillatorQ *= gain
            }
            for index in filtersI.indices { i = filtersI[index].push(i); q = filtersQ[index].push(q) }
            downsample += 1
            guard downsample == decimation else { continue }
            downsample = 0
            let power = i * i + q * q
            if power < threshold * threshold / 4 {
                quiet += 1
                if quiet == Int(demodRate * 0.05) {
                    for index in clocks.indices { clocks[index].reset() }
                    havePrevious = false
                }
            } else { quiet = 0 }
            if quiet >= Int(demodRate * 0.05) { continue }
            defer { previousI = i; previousQ = q; havePrevious = true }
            guard havePrevious else { continue }
            let cross = previousI * q - previousQ * i, dot = previousI * i + previousQ * q
            let frequency = atan2(cross, dot) * demodRate / (2 * .pi)
            let time = Double(inputSamples) / sampleRate
            for index in clocks.indices {
                if let frame = clocks[index].push(frequency: frequency, time: time) { publish(frame) }
            }
        }
    }

    /// Incomplete trailing words are deliberately discarded; no padding is accepted as data.
    func finish() { for index in clocks.indices { clocks[index].reset() } }

    private func publish(_ frame: DGPSReception) {
        // A message can be recovered by several phase banks. Keep actual repeats;
        // suppress only copies ending within 80 ms, much less than the shortest frame.
        let key = "\(frame.bitRate):\(frame.stationID):\(frame.messageType):\(frame.zCountSeconds):\(frame.sequence):\(frame.stationHealth):\(frame.payloadWords)"
        guard !recent.contains(where: { $0.key == key && abs($0.time - frame.sampleOffsetSeconds) < 0.08 }) else { return }
        recent.append((key, frame.sampleOffsetSeconds)); if recent.count > 64 { recent.removeFirst(recent.count - 64) }
        receptions.append(frame); if receptions.count > 64 { receptions.removeFirst(receptions.count - 64) }
        acceptedFrames += 1
        text += frame.monitorLine + "\n\n"
        if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
    }

    var status: String {
        let rates = Set(clocks.map(\.bitRate)).sorted().map(String.init).joined(separator: "/")
        return "MSK \(rates) bit/s · \(acceptedFrames) mensajes RTCM2 con paridad · sin solución de navegación"
    }
}
