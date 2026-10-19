import CoreGraphics
import Foundation

/// Fixed-size history: colour each new row once, then scroll the existing pixels.
/// Each CGImage owns a snapshot; later appends cannot change an image being drawn.
struct WaterfallRaster {
    let width = 256
    let height = 80
    private var pixels: [UInt8] = []

    mutating func reset() { pixels.removeAll(keepingCapacity: true) }

    mutating func append(_ bins: [Float]) -> CGImage? {
        guard !bins.isEmpty else { return nil }
        let rowBytes = width * 4
        if pixels.isEmpty {
            pixels = [UInt8](repeating: 0, count: rowBytes * height)
            for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        }
        pixels.withUnsafeMutableBytes { storage in
            guard let base = storage.baseAddress else { return }
            memmove(base.advanced(by: rowBytes), base, rowBytes * (height - 1))
        }
        for column in 0..<width {
            let db = bins[min(bins.count - 1, column * bins.count / width)]
            let value = db.isFinite ? min(1, max(0, (Double(db) + 80) / 70)) : 0
            let offset = column * 4
            pixels[offset] = UInt8(30 * value)
            pixels[offset + 1] = UInt8(190 * value)
            pixels[offset + 2] = UInt8(255 * value)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
