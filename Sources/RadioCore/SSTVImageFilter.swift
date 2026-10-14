import Foundation

public struct SSTVCalibration: Codable, Sendable {
    public let clockPPM: Double
    public let centerHz: Double
    public let syncLines: Int
    public let jitterMilliseconds: Double
}

enum SSTVImageFilter {
    static func apply(_ pixels: [UInt8], width: Int, height: Int, reduction: SSTVNoiseReduction) -> [UInt8] {
        guard reduction != .off, width >= 3, height >= 3 else { return pixels }
        var output = pixels
        for row in 1..<(height - 1) {
            for column in 1..<(width - 1) {
                let base = (row * width + column) * 3
                for channel in 0..<3 {
                    let index = base + channel
                    let a = Int(pixels[index - 3]), b = Int(pixels[index + 3])
                    let c = Int(pixels[index - width * 3]), d = Int(pixels[index + width * 3])
                    let center = Int(pixels[index])
                    let median = [a,b,c,d,center].sorted()[2]
                    // Balanced removes isolated impulses supported by four
                    // similar neighbours; edges and thin lines survive.
                    if reduction == .strong || (max(a,b,c,d) - min(a,b,c,d) < 80 && abs(center - median) > 48) {
                        output[index] = UInt8(median)
                    }
                }
            }
        }
        return output
    }
}
