import Foundation

// Protocol facts: ITU-R M.476-5 Table 1/2 and M.625-4 §4.
// A code is assembled LSB first, B (higher tone) = 1, Y (lower tone) = 0.
enum CCIR476 {
    static let alpha: UInt8 = 0x0F, repeatSignal: UInt8 = 0x66
    static let lettersShift: UInt8 = 0x5A, figuresShift: UInt8 = 0x36
    static func valid(_ code: UInt8) -> Bool { code < 128 && code.nonzeroBitCount == 4 }
    static func idle(_ code: UInt8) -> Bool { code == alpha || code == repeatSignal || code == 0x33 || code == 0x6A }
    static let letters: [UInt8: UInt8] = [
        0x47:65, 0x72:66, 0x1D:67, 0x53:68, 0x56:69, 0x1B:70,
        0x35:71, 0x69:72, 0x4D:73, 0x17:74, 0x1E:75, 0x65:76,
        0x39:77, 0x59:78, 0x71:79, 0x2D:80, 0x2E:81, 0x55:82,
        0x4B:83, 0x74:84, 0x4E:85, 0x3C:86, 0x27:87, 0x3A:88,
        0x2B:89, 0x63:90, 0x5C:32, 0x78:13, 0x6C:10
    ]
    // International figures. F/G/H are unassigned in M.476; D is WRU.
    // National alphabets can assign these positions differently.
    static let figures: [UInt8: UInt8] = [
        0x47:45, 0x72:63, 0x1D:58, 0x56:51, 0x4D:56, 0x17:7,
        0x1E:40, 0x65:41, 0x39:46, 0x59:44, 0x71:57, 0x2D:48,
        0x2E:49, 0x55:52, 0x4B:39, 0x74:53, 0x4E:55, 0x3C:61,
        0x27:50, 0x3A:47, 0x2B:54, 0x63:43, 0x5C:32, 0x78:13, 0x6C:10
    ]
}

// Stream of seven-bit constant-weight words and five-slot FEC time diversity.
// Only collective B mode is accepted; selective B / SITOR-A are separate modes.
final class CCIR476Receiver {
    private var recentBits: UInt32 = 0, recentUnknown: UInt32 = 0
    private var receivedBits = 0, wordBits = 0
    private var word: UInt8 = 0, wordUnknown = false
    private var history = [UInt8](repeating: 0, count: 5)
    private var historyIndex = 0, historyCount = 0
    private var firstCopySlot = true, figures = false, invalidRun = 0
    private(set) var locked = false
    private(set) var text = ""
    private(set) var corrected = 0, erased = 0, disagreements = 0, resynchronizations = 0

    func loseSignal() {
        if locked { resynchronizations += 1 }
        locked = false; recentBits = 0; recentUnknown = 0; receivedBits = 0
        wordBits = 0; word = 0; wordUnknown = false
        historyCount = 0; historyIndex = 0; invalidRun = 0
    }

    func push(bit: Bool?) {
        recentBits = (recentBits >> 1) | ((bit == true ? 1 : 0) << 27)
        recentUnknown = (recentUnknown >> 1) | ((bit == nil ? 1 : 0) << 27)
        receivedBits = min(28, receivedBits + 1)
        if !locked {
            guard receivedBits == 28, recentUnknown == 0 else { return }
            let a = UInt8(recentBits & 127), b = UInt8((recentBits >> 7) & 127), c = UInt8((recentBits >> 14) & 127)
            let d = UInt8((recentBits >> 21) & 127)
            guard a == c, b == d, (a == CCIR476.alpha && b == CCIR476.repeatSignal) ||
                    (a == CCIR476.repeatSignal && b == CCIR476.alpha) else { return }
            locked = true; figures = false
            // REP is the first-copy slot; ALPHA is the second-copy slot.
            firstCopySlot = d == CCIR476.alpha
            wordBits = 0; word = 0; wordUnknown = false; historyCount = 0; historyIndex = 0
            return
        }
        if bit == true { word |= 1 << wordBits }
        if bit == nil { wordUnknown = true }
        wordBits += 1
        guard wordBits == 7 else { return }
        accept(wordUnknown ? 0 : word)
        wordBits = 0; word = 0; wordUnknown = false
    }

    private func accept(_ code: UInt8) {
        let old = historyCount >= 5 ? history[historyIndex] : nil
        history[historyIndex] = code; historyIndex = (historyIndex + 1) % 5
        historyCount = min(5, historyCount + 1)
        invalidRun = CCIR476.valid(code) ? 0 : invalidRun + 1
        if !firstCopySlot, let old {
            if old == CCIR476.repeatSignal && code == CCIR476.alpha {
                firstCopySlot.toggle()
                return
            }
            let firstValid = CCIR476.valid(old), secondValid = CCIR476.valid(code)
            if firstValid && secondValid {
                if old == code { append(code) }
                else { disagreements += 1; erasure() }
            } else if firstValid || secondValid {
                let recovered = firstValid ? old : code
                if !CCIR476.idle(recovered) { corrected += 1 }
                append(recovered)
            } else { erasure() }
        }
        firstCopySlot.toggle()
        if invalidRun >= 10 { loseSignal() }
    }
    private func erasure() { erased += 1; appendText("�") }
    private func append(_ code: UInt8) {
        switch code {
        case CCIR476.lettersShift: figures = false
        case CCIR476.figuresShift: figures = true
        case CCIR476.alpha, CCIR476.repeatSignal, 0x33, 0x6A: break
        default:
            guard let value = (figures ? CCIR476.figures : CCIR476.letters)[code] else { appendText("□"); return }
            // CR/LF is rendered as one line break. BELL has no audible action.
            if value != 13 && value != 7 { appendText(String(UnicodeScalar(value))) }
        }
    }
    private func appendText(_ value: String) {
        text.append(value)
        if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
    }
    var status: String {
        "\(locked ? "CCIR 476 sincronizado" : "Buscando phasing CCIR 476") · FEC: \(corrected) recuperados · \(erased) ilegibles · \(disagreements) discrepancias"
    }
}

final class SITORBDecoder {
    private var analytic: AnalyticAudio
    private let receiver = CCIR476Receiver()
    private let center: Double, threshold: Double, inverted: Bool, smoothing: Double
    private var filteredFrequency = 0.0, previousBit: Bool?
    private var nextCenter: Double?, lastSignal = 0.0
    private let period = 0.010
    init(sampleRate: Double, settings: DecoderSettings) {
        analytic = AnalyticAudio(sampleRate: sampleRate)
        center = settings.frequency; threshold = settings.threshold
        inverted = settings.inverted; smoothing = 1 - exp(-1 / (sampleRate * 0.001))
    }
    func process(_ samples: [Float]) {
        for sample in samples {
            guard let value = analytic.push(sample) else { continue }
            let active = value.amplitude >= threshold && value.frequency.isFinite
            if active {
                lastSignal = value.time
                let deviation = min(170, max(-170, value.frequency - center))
                filteredFrequency += smoothing * (deviation - filteredFrequency)
            }
            if value.time - lastSignal > 0.2 {
                if nextCenter != nil { receiver.loseSignal() }
                nextCenter = nil; previousBit = nil; filteredFrequency = 0
                continue
            }
            guard active || nextCenter != nil else { continue }
            let decision = (filteredFrequency >= 0) != inverted
            if nextCenter == nil { nextCenter = value.time + period / 2 }
            if active, let previousBit, previousBit != decision, let scheduled = nextCenter {
                // Transitions identify bit boundaries. Pull the sample clock
                // gradually, preserving one decision per 10 ms through noise.
                let target = value.time + period / 2
                var error = (target - scheduled).truncatingRemainder(dividingBy: period)
                if error > period / 2 { error -= period }
                if error < -period / 2 { error += period }
                nextCenter = scheduled + 0.15 * error
            }
            if active { previousBit = decision }
            if let scheduled = nextCenter, value.time >= scheduled {
                receiver.push(bit: active ? decision : nil)
                nextCenter = scheduled + period
            }
        }
    }
    var text: String { receiver.text }
    var status: String { receiver.status }
}
