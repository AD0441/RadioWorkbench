import Foundation

final class APTDecoder {
    private let sampleRate: Double
    private let clockStep: Double
    private var clock = 0.0, amplitudeSum = 0.0, amplitudeCount = 0
    private var words: [Double] = []
    private var lineStart: Int?
    private var bestPosition = 0, bestScore = 0.0
    private var pixels: [UInt8] = []
    private var lines = 0
    private(set) var status = "APT · buscando sincronía A a 4160 palabras/s…"
    private static let sync: [Double] = Array(repeating: -1.0, count: 4) + (0..<7).flatMap { _ in [1.0, 1.0, -1.0, -1.0] } + Array(repeating: -1.0, count: 7)
    init(sampleRate: Double, settings: DecoderSettings) {
        self.sampleRate = sampleRate
        clockStep = 4160 * (1 + settings.imageClockPPM * 0.000001) / sampleRate
        words.reserveCapacity(6240)
    }
    func push(amplitude: Double) {
        amplitudeSum += amplitude; amplitudeCount += 1; clock += clockStep
        guard clock >= 1 else { return }
        clock -= 1
        words.append(amplitudeSum / Double(amplitudeCount)); amplitudeSum = 0; amplitudeCount = 0
        if lineStart == nil, words.count >= 39 {
            let position = words.count - 39
            let score = correlation(at: position)
            if score > 0.72 && score > bestScore { bestScore = score; bestPosition = position }
            if bestScore > 0.72 && position > bestPosition + 45 { lineStart = bestPosition }
            if words.count > 6240, lineStart == nil {
                words.removeFirst(2080); bestPosition = max(0, bestPosition - 2080); bestScore = 0
            }
        }
        guard let start = lineStart, words.count >= start + 2080 else { return }
        guard correlation(at: start) >= 0.5 else {
            words.removeFirst(min(start + 39, words.count)); lineStart = nil; bestScore = 0; bestPosition = 0
            return
        }
        let row = Array(words[start..<start + 2080])
        render(row)
        words.removeFirst(start + 2080)
        lineStart = 0
    }
    private func correlation(at start: Int) -> Double {
        let values = words[start..<start + 39]
        let mean = values.reduce(0, +) / 39
        let templateMean = Self.sync.reduce(0, +) / 39
        var dot = 0.0, energy = 0.0, templateEnergy = 0.0
        for (i, value) in values.enumerated() {
            let a = value - mean, b = Self.sync[i] - templateMean
            dot += a * b; energy += a * a; templateEnergy += b * b
        }
        return energy > 0.00001 ? dot / sqrt(energy * templateEnergy) : 0
    }
    private func render(_ words: [Double]) {
        guard lines < 4096 else { status = "APT · límite de 4096 líneas"; return }
        let low = (0..<39).filter { Self.sync[$0] < 0 }.map { words[$0] }.sorted()
        let high = (0..<39).filter { Self.sync[$0] > 0 }.map { words[$0] }.sorted()
        let black = low[low.count / 2], white = high[high.count / 2]
        let scale = max(0.00001, (white - black) / 233)
        let zero = black - 11 * scale
        // Decode the two 909-pixel video regions, excluding sync, space and telemetry.
        for region in [86..<995, 1126..<2035] {
            for index in region {
                let gray = UInt8(min(255, max(0, (words[index] - zero) / scale)))
                pixels.append(contentsOf: [gray, gray, gray])
            }
        }
        lines += 1; status = "APT · canales A y B · \(lines) líneas · sincronía A detectada"
    }
    var image: RadioImage? {
        guard lines > 0 else { return nil }
        return RadioImage(width: 1818, height: lines, rgb: pixels, caption: status)
    }
}
