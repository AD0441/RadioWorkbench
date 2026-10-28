import Foundation

// Compile -O with production SpectrumAnalyzer.swift and the AudioBlockQuality
// definition from InputQuality.swift. Compare the same sources from the base
// revision and the candidate. This measures CPU analysis, not SwiftUI/display.
@main struct SpectrumBenchmark {
    static func main() throws {
        let analyzer = SpectrumAnalyzer()
        let samples = (0..<2048).map { Float(0.25 * sin(2 * .pi * 1500 * Double($0) / 48000)) }
        for _ in 0..<200 { _ = analyzer.analyze(samples, sampleRate: 48000) }
        var times: [Double] = [], checksum = 0.0
        for _ in 0..<5000 {
            let start = ProcessInfo.processInfo.systemUptime
            let frame = analyzer.analyze(samples, sampleRate: 48000)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000_000)
            checksum += frame.peakFrequency + frame.levelDB
        }
        times.sort()
        let result: [String: Any] = ["iterations": times.count,"median_us":times[times.count/2],"p95_us":times[Int(Double(times.count)*0.95)],"checksum":checksum,"scope":"CPU spectrum analysis, 2048 samples at 48 kHz; excludes UI, RF and audio-device latency"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
