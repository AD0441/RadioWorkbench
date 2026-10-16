import Foundation

private struct HellLowPass {
    let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var z1 = 0.0, z2 = 0.0
    init(rate: Double, cutoff: Double, q: Double) {
        let w = 2 * Double.pi * cutoff / rate, c = cos(w), alpha = sin(w) / (2 * q), gain = 1 / (1 + alpha)
        b0 = (1 - c) / 2 * gain; b1 = (1 - c) * gain; b2 = b0
        a1 = -2 * c * gain; a2 = (1 - alpha) * gain
    }
    mutating func push(_ value: Double) -> Double {
        let out = b0 * value + z1; z1 = b1 * value - a1 * out + z2; z2 = b2 * value - a2 * out
        return out
    }
}
/// Independent OOK visual raster receiver. No character recognition or framing is invented.
final class HellDecoder {
    private let settings: DecoderSettings, sampleRate: Double, phaseStep: Double, pixelStep: Double, peakDecay: Double
    private var filtersI: [HellLowPass], filtersQ: [HellLowPass]
    private var phase = 0.0, sampleCount = 0.0, nextPixel = 0.0, pixelSum = 0.0, pixelCount = 0, peak = 0.0
    private var rows: [UInt8] = [], columns: [[UInt8]] = []
    private(set) var totalColumns = 0
    private static let columnsPerStrip = 160, maximumColumns = 1280
    init(sampleRate: Double, settings: DecoderSettings) {
        self.sampleRate = sampleRate; self.settings = settings
        phaseStep = 2 * .pi * settings.frequency / sampleRate
        pixelStep = sampleRate / settings.hellVariant.pixelRate * (1 + settings.imageClockPPM * 1e-6)
        nextPixel = settings.imageStartSeconds * sampleRate + pixelStep
        peakDecay = exp(-1 / (sampleRate * 3))
        let cutoff = min(sampleRate * 0.4, settings.hellVariant.pixelRate * 0.9)
        filtersI = [0.5411961, 1.306563].map { HellLowPass(rate: sampleRate, cutoff: cutoff, q: $0) }
        filtersQ = filtersI
    }
    func process(_ samples: [Float]) {
        for sample in samples {
            let value = sample.isFinite ? Double(sample) : 0
            var i = value * cos(phase), q = value * sin(phase)
            phase += phaseStep; if phase >= 2 * .pi { phase -= 2 * .pi }
            for index in filtersI.indices { i = filtersI[index].push(i); q = filtersQ[index].push(q) }
            let amplitude = 2 * hypot(i, q)
            peak = max(amplitude, peak * peakDecay)
            sampleCount += 1
            guard sampleCount > settings.imageStartSeconds * sampleRate else { continue }
            pixelSum += amplitude; pixelCount += 1
            if sampleCount >= nextPixel {
                let average = pixelSum / Double(max(1, pixelCount))
                let scale = max(settings.threshold * 4, peak * 0.8)
                let ink = min(1, max(0, (average - settings.threshold) / max(1e-8, scale - settings.threshold)))
                let grey = UInt8((255 * (settings.inverted ? ink : 1 - ink)).rounded())
                rows.append(grey); pixelSum = 0; pixelCount = 0; nextPixel += pixelStep
                if rows.count == 14 { commitColumn() }
            }
        }
    }
    private func commitColumn() {
        columns.append(rows); rows.removeAll(keepingCapacity: true); totalColumns += 1
        if columns.count > Self.maximumColumns { columns.removeFirst(Self.columnsPerStrip) }
    }
    func finish() {
        if !rows.isEmpty { rows += Array(repeating: settings.inverted ? 0 : 255, count: 14 - rows.count); commitColumn() }
    }
    var status: String { "\(settings.hellVariant.rawValue) · \(totalColumns) columnas · raster visual sin OCR" }
    var image: RadioImage? {
        guard !columns.isEmpty else { return nil }
        let width = min(Self.columnsPerStrip, columns.count) * 2
        let strips = (columns.count + Self.columnsPerStrip - 1) / Self.columnsPerStrip, height = strips * 28
        var rgb = [UInt8](repeating: settings.inverted ? 0 : 255, count: width * height * 3)
        for (index, column) in columns.enumerated() {
            let x = (index % Self.columnsPerStrip) * 2, y = (index / Self.columnsPerStrip) * 28
            let previous = index > 0 ? columns[index - 1] : Array(repeating: settings.inverted ? UInt8(0) : UInt8(255), count: 14)
            for row in 0..<14 {
                for copy in 0..<2 {
                    let grey = copy == 0 ? previous[row] : column[row]
                    let offset = ((y + copy * 14 + 13 - row) * width + x) * 3
                    for dx in 0..<2 { rgb[offset + dx * 3] = grey; rgb[offset + dx * 3 + 1] = grey; rgb[offset + dx * 3 + 2] = grey }
                }
            }
        }
        return RadioImage(width: width, height: height, rgb: rgb, caption: status + " · doble trazo · últimas \(columns.count) columnas · inicio y reloj manuales")
    }
}
