import Foundation

struct RTTYDecoder {
    private var mark: ToneDetector
    private var space: ToneDetector
    private let tick: Double, bit: Double, threshold: Double
    private let inverted: Bool
    private let encoding: RTTYEncoding
    private var time = 0.0, next = 0.0
    private var state = -1, value = 0
    private var figures = false
    private var previousMark = true
    private(set) var text = ""
    private(set) var transitions = 0
    private(set) var markLevel = 0.0, spaceLevel = 0.0
    // ITU-T S.1 / ITA2. Data is sent least significant bit first.
    static let letters = Array("\0E\nA SIU\rDRJNFCKTZLWHYPQOBG\0MXV\0")
    static let numbers = Array("\03\n- '87\r$4\u{7},!:(5\")2#6019?&\0./;\0")
    init(sampleRate: Double, settings: DecoderSettings) {
        let duration = min(0.004, 0.22 / settings.baud)
        mark = ToneDetector(frequency: settings.frequency + settings.shift / 2, sampleRate: sampleRate, duration: duration)
        space = ToneDetector(frequency: settings.frequency - settings.shift / 2, sampleRate: sampleRate, duration: duration)
        tick = Double(mark.length) / sampleRate
        bit = 1 / settings.baud; threshold = settings.threshold; inverted = settings.inverted
        encoding = settings.rttyEncoding
    }
    mutating func push(_ sample: Float) {
        let m = mark.push(sample), s = space.push(sample)
        guard let m, let s else { return }
        markLevel = m; spaceLevel = s; time += tick
        guard max(m, s) >= threshold else { state = -1; previousMark = true; return }
        let isMark = (m >= s) != inverted
        if isMark != previousMark { transitions += 1 }
        if state == -1 {
            if previousMark && !isMark { state = 0; next = time + bit / 2; value = 0 }
        } else if time >= next {
            if state == 0 {
                if isMark { state = -1 } else { state = 1; next += bit }
            } else if state <= encoding.dataBits {
                if isMark { value |= 1 << (state - 1) }
                state += 1; next += bit
            } else {
                if isMark { append(value) }
                state = -1
            }
        }
        previousMark = isMark
    }
    private mutating func append(_ code: Int) {
        if encoding != .ita2 {
            if code == 10 || code == 9 || (32...126).contains(code), let scalar = UnicodeScalar(code) { text.unicodeScalars.append(scalar) }
            if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
            return
        }
        switch code {
        case 31: figures = false
        case 27: figures = true
        case 0: break
        default:
            let table = figures ? Self.numbers : Self.letters
            if code < table.count, table[code] != "\0", table[code] != "\r", table[code] != "\u{7}" { text.append(table[code]) }
            if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
        }
    }
}
