import CoreGraphics
import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func visualTone(_ start: Int, count: Int = 2048) -> [Float] {
    (start..<start + count).map { Float(0.25 * sin(2 * .pi * 1500 * Double($0) / 48000)) }
}

@Test func liveSpectrumEmptyPollsDoNotConsumeVisualDeadlines() throws {
    let analyzer = LiveSpectrumAnalyzer(sampleRate: 48000)
    var frames = 0
    for index in 0..<72 {
        let time = Double(index) * 2048 / 48000
        if analyzer.append(visualTone(index * 2048), at: time) != nil { frames += 1 }
        #expect(analyzer.append([], at: time + 0.02) == nil)
    }
    #expect(frames == 72)
    let frame = try #require(analyzer.append(visualTone(0), at: 10))
    #expect(abs(frame.peakFrequency - 1500) < 24)
    // A long pause yields one fresh frame, without a catch-up burst.
    #expect(analyzer.append(visualTone(0), at: 10.001) == nil)
    analyzer.reset()
    #expect(analyzer.append(visualTone(0), at: 10.001) != nil)
}

@Test func liveSpectrumKeepsAFullWindowAcrossSmallAudioPacketsAndCapsRate() throws {
    let analyzer = LiveSpectrumAnalyzer(sampleRate: 48000)
    var last: SpectrumFrame?, count = 0
    for index in 0..<1000 {
        if let frame = analyzer.append(visualTone(index * 48, count: 48), at: Double(index) / 1000) {
            last = frame; count += 1
        }
    }
    #expect((24...26).contains(count))
    let frame = try #require(last)
    #expect(abs(frame.peakFrequency - 1500) < 24)
    let reference = SpectrumAnalyzer().analyze(visualTone(0), sampleRate: 48000)
    #expect(abs(frame.levelDB - reference.levelDB) < 0.1)
}

private func pixelData(_ image: CGImage) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data)
    return Array(data as Data)
}

@Test func waterfallScrollsWithFixedScaleRetainsImmutableSnapshotsAndResets() throws {
    var raster = WaterfallRaster()
    #expect(raster.append([]) == nil)
    let firstImage = raster.append([-10])
    let first = try #require(firstImage), original = try pixelData(first)
    #expect(first.width == 256 && first.height == 80)
    #expect(Array(original.prefix(4)) == [30, 190, 255, 255])
    #expect(Array(original[1024..<1028]) == [0, 0, 0, 255])
    for index in 0..<85 { _ = raster.append([Float(-80 + index % 70)]) }
    #expect(try pixelData(first) == original)
    let finalImage = raster.append([.nan, .infinity, -.infinity, -200, 10])
    let final = try #require(finalImage)
    let bytes = try pixelData(final)
    #expect(Array(bytes.prefix(4)) == [0, 0, 0, 255])
    #expect(Array(bytes.suffix(4)) != [0, 0, 0, 0])
    #expect(Array(bytes[(255 * 4)..<(256 * 4)]) == [30, 190, 255, 255])
    raster.reset()
    let resetImage = raster.append([-80])
    let reset = try #require(resetImage)
    #expect(try pixelData(reset).enumerated().allSatisfy { $0.element == ($0.offset % 4 == 3 ? 255 : 0) })
}

@Test func waterfallMatchesPreviousColourMappingAndHistoryOrder() throws {
    var raster = WaterfallRaster(), rows: [[Float]] = []
    var image: CGImage?
    for line in 0..<100 {
        let bins = (0..<700).map { Float(-110 + ($0 + line * 3) % 130) }
        rows.insert((0..<256).map { bins[$0 * bins.count / 256] }, at: 0)
        if rows.count > 80 { rows.removeLast() }
        image = raster.append(bins)
    }
    var reference: [UInt8] = []
    for row in rows {
        for db in row {
            let value = min(1, max(0, (Double(db) + 80) / 70))
            reference += [UInt8(30 * value), UInt8(190 * value), UInt8(255 * value), 255]
        }
    }
    #expect(try pixelData(#require(image)) == reference)
}

@Test @MainActor func liveVisualizationKeepsOnlyTheNewestPendingFrameAndRejectsPreviousSession() async throws {
    let visualization = ReceiverVisualization()
    let submit = visualization.startLive()
    let reference = SpectrumAnalyzer().analyze(visualTone(0), sampleRate: 48000)
    for index in 0..<1000 {
        let frame = SpectrumFrame(sampleRate: reference.sampleRate, quality: reference.quality, bins: reference.bins,
                                  upperFrequency: reference.upperFrequency, levelDB: reference.levelDB,
                                  peakFrequency: Double(index), clipped: false)
        submit(frame)
    }
    // The producer never awaits the main actor and cannot create 1000 UI tasks.
    await Task.yield()
    for _ in 0..<20 {
        if visualization.frame != nil { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(visualization.frame != nil && visualization.waterfall?.height == 80)
    #expect(visualization.frame?.peakFrequency == 999)
    visualization.reset()
    submit(SpectrumAnalyzer().analyze(visualTone(0), sampleRate: 48000))
    await Task.yield()
    #expect(visualization.frame == nil && visualization.waterfall == nil)
}
