import Foundation

struct PSK31Decoder {
    struct Candidate {
        var previousI = 0.0, previousQ = 0.0
        var word = 0, zeros = 0, bits = 0
        var energy = 0.0
        var invalid = 0
        var text = ""
        mutating func sample(i: Double, q: Double, threshold: Double) {
            let power = i * i + q * q
            guard power > threshold * threshold / 16 else {
                previousI = 0; previousQ = 0; word = 0; bits = 0; zeros = 0
                return
            }
            let dot = i * previousI + q * previousQ
            if previousI != 0 || previousQ != 0 { consume(dot >= 0) }
            energy += power
            previousI = i; previousQ = q
        }
        mutating func consume(_ one: Bool) {
            if one {
                zeros = 0; word = (word << 1) | 1; bits += 1
            } else {
                zeros += 1
                if zeros == 2 {
                    let code = word >> 1
                    if bits > 0 {
                        if let char = Varicode.decode[code], char == "\n" || char == "\t" || (char.asciiValue ?? 0) >= 32 {
                            if char != "\u{7f}" { text.append(char) }
                        } else if code != 31 { invalid += 1 }
                    }
                    word = 0; bits = 0
                } else if bits > 0 { word <<= 1; bits += 1 }
            }
            if bits > 12 { word = 0; bits = 0; invalid += 1 }
            if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
        }
    }
    private var phases = Array(repeating: Candidate(), count: 16)
    private var phaseIndex = 0
    private var oscillatorI = 1.0, oscillatorQ = 0.0
    private let rotateI: Double, rotateQ: Double, alpha: Double
    private var filteredI = 0.0, filteredQ = 0.0
    private var clock = 0.0
    private let clockStep: Double, threshold: Double
    init(sampleRate: Double, settings: DecoderSettings) {
        let angle = 2 * Double.pi * settings.frequency / sampleRate
        rotateI = cos(angle); rotateQ = sin(angle)
        alpha = 1 - exp(-2 * .pi * 45 / sampleRate)
        clockStep = 31.25 * 16 / sampleRate
        threshold = settings.threshold
    }
    mutating func push(_ sample: Float) {
        filteredI += alpha * (Double(sample) * oscillatorI - filteredI)
        filteredQ += alpha * (Double(sample) * oscillatorQ - filteredQ)
        let nextI = oscillatorI * rotateI - oscillatorQ * rotateQ
        oscillatorQ = oscillatorQ * rotateI + oscillatorI * rotateQ
        oscillatorI = nextI
        clock += clockStep
        if clock >= 1 {
            clock -= 1
            phases[phaseIndex].sample(i: filteredI, q: filteredQ, threshold: threshold)
            phaseIndex = (phaseIndex + 1) % 16
        }
    }
    var text: String {
        // Select symbol phase by observed envelope energy, penalizing bad codes.
        phases.max(by: { ($0.energy / Double(1 + $0.invalid)) < ($1.energy / Double(1 + $1.invalid)) })?.text ?? ""
    }
}
