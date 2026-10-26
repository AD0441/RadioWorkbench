import CoreGraphics
import Observation
import RadioCore

/// Only spectrum and meter views observe this frequently changing state.
@MainActor @Observable
final class ReceiverVisualization {
    private(set) var frame: SpectrumFrame?
    private(set) var waterfall: CGImage?
    @ObservationIgnored private var raster = WaterfallRaster()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncStream<SpectrumFrame>.Continuation?

    var warnClipping = true
    func configure(palette: String, lowPower: Bool, warnClipping: Bool) {
        self.warnClipping = warnClipping
        let height = lowPower ? 40 : 80
        guard raster.palette != palette || raster.height != height else { return }
        raster = WaterfallRaster(height: height, palette: palette); waterfall = nil
    }
    func update(_ frame: SpectrumFrame) {
        self.frame = frame
        waterfall = raster.append(frame.bins)
    }

    func reset() {
        stopLive(); frame = nil; waterfall = nil; raster.reset()
    }

    func startLive() -> @Sendable (SpectrumFrame) -> Void {
        stopLive()
        let (stream, continuation) = AsyncStream<SpectrumFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        task = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { break }
                self?.update(frame)
            }
        }
        return { frame in continuation.yield(frame) }
    }

    func stopLive() {
        continuation?.finish(); continuation = nil
        task?.cancel(); task = nil
    }

    deinit { task?.cancel(); continuation?.finish() }
}
