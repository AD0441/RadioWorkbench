import Foundation

// 4 ms coherent sync energy, at 0.5 ms hops. A pulse timestamp is the energy
// centroid, so its estimate does not depend on the UI or input buffer size.
struct SSTVLineSync {
    private var samples: [Double]
    private let rate: Double, hop: Int, coefficient: Double, timeOffset: Double
    private var position = 0, count = 0, tick = 0
    private var start: Double?, last = 0.0, sum = 0.0, weightedTime = 0.0
    init(sampleRate: Double, tone: Double, timeOffset: Double) {
        self.timeOffset = timeOffset
        rate = sampleRate; hop = max(1, Int((sampleRate * 0.0005).rounded()))
        samples = Array(repeating: 0, count: max(16, Int((sampleRate * 0.004).rounded())))
        coefficient = 2 * cos(2 * .pi * tone / sampleRate)
    }
    mutating func push(_ sample: Float, threshold: Double) -> (center: Double, duration: Double)? {
        samples[position] = Double(sample); position += 1; if position == samples.count { position = 0 }
        count += 1; tick += 1
        guard count >= samples.count, tick >= hop else { return nil }; tick = 0
        var s1 = 0.0, s2 = 0.0, total = 0.0, cursor = position
        for _ in samples.indices {
            let x = samples[cursor]; total += x * x
            let next = x + coefficient * s1 - s2; s2 = s1; s1 = next
            cursor += 1; if cursor == samples.count { cursor = 0 }
        }
        let power = max(0, s1 * s1 + s2 * s2 - coefficient * s1 * s2)
        let purity = total > 0 ? 2 * power / (Double(samples.count) * total) : 0
        let time = timeOffset + (Double(count - 1) - Double(samples.count - 1) / 2) / rate
        if purity >= 0.28, 2 * sqrt(power) / Double(samples.count) >= threshold / 2 {
            if start == nil { start = time; sum = 0; weightedTime = 0 }
            last = time; sum += purity; weightedTime += purity * time
        } else if let start, time - last > 0.001 {
            self.start = nil
            return (weightedTime / max(sum, 0.000001), last - start + Double(hop) / rate)
        }
        return nil
    }
}

struct SSTVTimingTracker {
    struct Fit { let anchor: Double, period: Double, count: Int, residual: Double }
    private var points: [(line: Int, time: Double)] = []
    private let nominalPeriod: Double, anchor: Double, initialPeriod: Double
    private(set) var fit: Fit?
    init(period: Double, anchor: Double, correction: Double) {
        nominalPeriod = period; self.anchor = anchor; initialPeriod = period / correction
    }
    mutating func observe(_ time: Double) -> Fit? {
        let period = fit?.period ?? initialPeriod
        let line: Int
        if let last = points.last {
            let difference = time - last.time
            let gap = Int((difference / period).rounded())
            guard (1...8).contains(gap), abs(difference - Double(gap) * period) < max(0.004, period * 0.06) else { return nil }
            line = last.line + gap
        } else {
            line = Int(((time - anchor) / period).rounded())
            guard (0...3).contains(line), abs(time - anchor - Double(line) * period) < period * 0.1 else { return nil }
        }
        guard points.count < 1024 else { return nil }
        points.append((line, time))
        guard points.count >= 8, points.count == 8 || points.count == 16 || points.count == 32 || points.count % 64 == 0 else { return nil }
        let meanX = points.reduce(0.0) { $0 + Double($1.line) } / Double(points.count)
        let meanY = points.reduce(0.0) { $0 + $1.time } / Double(points.count)
        var xx = 0.0, xy = 0.0
        for point in points { let x = Double(point.line) - meanX; xx += x * x; xy += x * (point.time - meanY) }
        guard xx > 0 else { return nil }
        let slope = xy / xx, intercept = meanY - slope * meanX
        let residual = sqrt(points.reduce(0.0) { $0 + pow($1.time - intercept - slope * Double($1.line), 2) } / Double(points.count))
        guard (0.95...1.05).contains(nominalPeriod / slope), residual < 0.0025 else { return nil }
        let result = Fit(anchor: intercept, period: slope, count: points.count, residual: residual)
        fit = result; return result
    }
}
