import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private final class VisualFrameTimes: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Double] = []
    func receive(_ frame: SpectrumFrame) {
        lock.lock(); defer { lock.unlock() }
        times.append(ProcessInfo.processInfo.systemUptime)
    }
    var value: [Double] { lock.lock(); defer { lock.unlock() }; return times }
}

// Opt-in measurement, not a timing assertion in the ordinary test suite.
// Feeds the actual live worker without opening a microphone or audio output.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RWB_VISUALIZATION_BENCHMARK"] != nil))
func liveVisualizationBenchmark() async throws {
    let ring = try AudioSampleRing(capacity: 131072), frames = VisualFrameTimes()
    let block = (0..<2048).map { Float(0.25 * sin(2 * .pi * 1500 * Double($0) / 48000)) }
    let started = ProcessInfo.processInfo.systemUptime
    let producer = Task.detached {
        for index in 0..<72 {
            ring.writeMono(block)
            let delay = started + Double(index + 1) * 2048 / 48000 - ProcessInfo.processInfo.systemUptime
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
        ring.finish()
    }
    var settings = DecoderSettings(); settings.digitalVoiceProtocol = .dmr
    try await RadioWorker().decodeLive(ring: ring, sampleRate: 48000, mode: .digitalVoice, settings: settings, source: "Synthetic live benchmark", visualize: { frames.receive($0) }) { _ in }
    try await producer.value
    let times = frames.value, gaps = zip(times.dropFirst(), times).map(-).sorted()
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let report: [String: Any] = ["frames": times.count, "input_seconds": 72.0 * 2048 / 48000,
        "elapsed_seconds": elapsed, "frames_per_input_second": Double(times.count) / (72.0 * 2048 / 48000),
        "median_gap_ms": gaps.isEmpty ? 0 : gaps[gaps.count / 2] * 1000,
        "max_gap_ms": (gaps.last ?? 0) * 1000, "samples_written": ring.written, "samples_dropped": ring.dropped]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print("LIVE_VISUALIZATION_BENCHMARK " + String(decoding: json, as: UTF8.self))
    #expect(ring.dropped == 0 && ring.written == 72 * 2048)
}
