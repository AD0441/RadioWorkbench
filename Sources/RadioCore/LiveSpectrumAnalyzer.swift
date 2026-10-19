import Foundation

/// Worker-owned, bounded analysis history. Audio callbacks only write their ring.
/// Visual time is independent of decoder/log publication, and empty polls do not
/// consume a visual deadline. A late consumer skips deadlines rather than replaying.
public final class LiveSpectrumAnalyzer {
    private let analyzer = SpectrumAnalyzer()
    private let sampleRate: Double
    private let interval = 1.0 / 25
    private var history = [Float](repeating: 0, count: 2048)
    private var ordered = [Float](repeating: 0, count: 2048)
    private var cursor = 0
    private var valid = 0
    private var deadline: Double?

    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    public func reset() {
        cursor = 0; valid = 0; deadline = nil
    }

    public func append(_ samples: [Float], at time: Double = ProcessInfo.processInfo.systemUptime) -> SpectrumFrame? {
        guard !samples.isEmpty else { return nil }
        // Only the latest FFT window is needed, even after an audio backlog.
        for sample in samples.suffix(history.count) {
            history[cursor] = sample; cursor = (cursor + 1) % history.count
        }
        valid = min(history.count, valid + samples.count)
        if let deadline, time < deadline { return nil }
        deadline = time + interval
        let start = (cursor - valid + history.count) % history.count
        for index in 0..<valid { ordered[index] = history[(start + index) % history.count] }
        return analyzer.analyze(valid == history.count ? ordered : Array(ordered.prefix(valid)), sampleRate: sampleRate)
    }
}
