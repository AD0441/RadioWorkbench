import Foundation

final class WEFAXDecoder {
    private let settings: DecoderSettings
    private let width: Int
    private var pixels: [UInt8] = []
    private var sums: [Double]
    private var counts: [Int]
    private var currentRow = 0
    private var completedRows = 0
    init(settings: DecoderSettings) {
        self.settings = settings
        width = Int((Double(settings.faxIOC) * .pi).rounded())
        sums = Array(repeating: 0, count: width); counts = Array(repeating: 0, count: width)
    }
    func push(frequency: Double, amplitude: Double, time: Double) {
        guard time >= settings.imageStartSeconds, amplitude >= settings.threshold / 2 else { return }
        let elapsed = (time - settings.imageStartSeconds) * (1 + settings.imageClockPPM * 0.000001)
        let lines = elapsed * settings.faxLinesPerMinute / 60
        let row = Int(lines)
        guard row < 4096 else { return }
        if row != currentRow {
            flushRow()
            currentRow = row
            sums = Array(repeating: 0, count: width); counts = Array(repeating: 0, count: width)
        }
        let column = min(width - 1, Int((lines - Double(row)) * Double(width)))
        let value = min(255, max(0, (frequency - 1500) / 800 * 255))
        sums[column] += settings.inverted ? 255 - value : value; counts[column] += 1
    }
    private func flushRow() {
        guard completedRows <= currentRow else { return }
        for i in 0..<width {
            let gray = counts[i] > 0 ? UInt8(sums[i] / Double(counts[i])) : 0
            pixels.append(contentsOf: [gray, gray, gray])
        }
        completedRows += 1
    }
    func finish() {
        // Filter ringing after the last tone must not create a spurious image row.
        if counts.filter({ $0 > 0 }).count >= max(16, width / 32) { flushRow() }
    }
    var status: String { "WEFAX · \(Int(settings.faxLinesPerMinute)) LPM · IOC \(settings.faxIOC) · inicio manual · \(completedRows) líneas" }
    var image: RadioImage? {
        guard completedRows > 0 else { return nil }
        return RadioImage(width: width, height: completedRows, rgb: pixels, caption: status)
    }
}
