import Foundation

struct DTMFDecoder {
    private var detectors: [ToneDetector]
    private let threshold: Double
    private var last: Int? = nil
    private var held = 0, blank = 0
    private var levels = Array(repeating: 0.0, count: 8)
    private(set) var text = ""
    private static let keys = Array("123A456B789C*0#D")
    init(sampleRate: Double, settings: DecoderSettings) {
        detectors = [697, 770, 852, 941, 1209, 1336, 1477, 1633].map {
            ToneDetector(frequency: Double($0), sampleRate: sampleRate, duration: 0.02)
        }
        threshold = settings.threshold
    }
    mutating func push(_ sample: Float) {
        var ready = false
        for i in detectors.indices {
            if let value = detectors[i].push(sample) { levels[i] = value; ready = true }
        }
        guard ready else { return }
        let low = (0..<4).max(by: { levels[$0] < levels[$1] })!
        let high = (4..<8).max(by: { levels[$0] < levels[$1] })!
        let lowOther = (0..<4).filter { $0 != low }.map { levels[$0] }.max() ?? 0
        let highOther = (4..<8).filter { $0 != high }.map { levels[$0] }.max() ?? 0
        let twist = levels[low] / max(0.0001, levels[high])
        guard levels[low] > threshold, levels[high] > threshold,
              levels[low] > 2 * lowOther, levels[high] > 2 * highOther, (0.25...4).contains(twist) else {
            blank += 1
            if blank >= 2 { last = nil; held = 0 }
            return
        }
        blank = 0
        let key = low * 4 + high - 4
        if last == key { held += 1 } else { last = key; held = 1 }
        if held == 2 {
            text.append(Self.keys[key])
            if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
        }
    }
}
