import CoreGraphics
import Foundation

// Compile in release with the production WaterfallRaster.swift. The reference
// below is the 0.12.0 implementation, including row mapping and image creation.
private func previousImage(_ rows: [[Float]]) -> CGImage? {
    var bytes = [UInt8](); bytes.reserveCapacity(rows.count * 256 * 4)
    for row in rows {
        for db in row {
            let value = min(1, max(0, (Double(db) + 80) / 70))
            bytes.append(UInt8(30 * value)); bytes.append(UInt8(190 * value)); bytes.append(UInt8(255 * value)); bytes.append(255)
        }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(width: 256, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

@main struct WaterfallBenchmark {
    static func main() throws {
        let bins = (0..<256).map { Float(-100 + $0 % 100) }
        var rows = [[Float]](repeating: bins, count: 80), raster = WaterfallRaster()
        for _ in 0..<80 { _ = raster.append(bins) }
        var results: [String: Any] = [:], checksum = 0
        for kind in ["previous", "incremental"] {
            var times: [Double] = []
            for _ in 0..<3000 {
                let start = ProcessInfo.processInfo.systemUptime
                let image: CGImage?
                if kind == "previous" {
                    let row = (0..<256).map { bins[min(bins.count - 1, $0 * bins.count / 256)] }
                    rows.insert(row, at: 0); if rows.count > 80 { rows.removeLast() }
                    image = previousImage(rows)
                } else { image = raster.append(bins) }
                checksum += image?.height ?? 0
                times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000_000)
            }
            times.sort()
            results[kind] = ["iterations": times.count, "mean_us": times.reduce(0, +) / Double(times.count),
                             "median_us": times[times.count / 2], "p95_us": times[Int(Double(times.count) * 0.95)]]
        }
        results["checksum"] = checksum
        results["scope"] = "CPU raster construction, 256x80 RGBA; excludes SwiftUI layout and display presentation"
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
