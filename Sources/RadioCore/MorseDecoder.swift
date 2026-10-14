import Foundation

struct MorseDecoder {
    private var detector: ToneDetector
    private let tick: Double
    private let unit: Double
    private let threshold: Double
    private var keyed = false
    private var duration = 0.0
    private var code = ""
    private var wordGapSent = true
    private(set) var text = ""
    static let alphabet: [String: String] = [
        ".-":"A", "-...":"B", "-.-.":"C", "-..":"D", ".":"E", "..-.":"F", "--.":"G", "....":"H", "..":"I", ".---":"J", "-.-":"K", ".-..":"L", "--":"M", "-.":"N", "---":"O", ".--.":"P", "--.-":"Q", ".-.":"R", "...":"S", "-":"T", "..-":"U", "...-":"V", ".--":"W", "-..-":"X", "-.--":"Y", "--..":"Z",
        "-----":"0", ".----":"1", "..---":"2", "...--":"3", "....-":"4", ".....":"5", "-....":"6", "--...":"7", "---..":"8", "----.":"9",
        ".-.-.-":".", "--..--":",", "..--..":"?", "-..-.":"/", "-...-":"=", ".-.-.":"+", ".--.-.":"@"
    ]
    init(sampleRate: Double, settings: DecoderSettings) {
        detector = ToneDetector(frequency: settings.frequency, sampleRate: sampleRate, duration: 0.005)
        tick = Double(detector.length) / sampleRate
        unit = 1.2 / settings.wordsPerMinute
        threshold = settings.threshold
    }
    mutating func push(_ sample: Float) {
        guard let amplitude = detector.push(sample) else { return }
        let next = amplitude > threshold * (keyed ? 0.8 : 1)
        if next != keyed {
            if keyed && duration >= tick * 2 {
                code += duration < 2 * unit ? "." : "-"
                if code.count > 8 { code = "" }
                wordGapSent = false
            }
            keyed = next; duration = 0
        }
        duration += tick
        if !keyed && duration >= 2.5 * unit { flushCharacter() }
        if !keyed && duration >= 6 * unit && !wordGapSent {
            text += " "; wordGapSent = true
        }
    }
    private mutating func flushCharacter() {
        guard !code.isEmpty else { return }
        text += Self.alphabet[code] ?? "�"; code = ""
        if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
    }
    mutating func finish() {
        if keyed && duration >= tick * 2 { code += duration < 2 * unit ? "." : "-" }
        flushCharacter()
    }
}
