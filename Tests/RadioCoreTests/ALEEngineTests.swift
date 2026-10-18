import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func aleFixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
}
private func writeALEFixture(_ name: String, to engine: ExternalAudioEngine) throws {
    let reader = try AudioFileReader(url: aleFixture(name))
    #expect(reader.sampleRate == 8000)
    while let samples = try reader.next() { try engine.write(samples) }
}

@Test(arguments: ["ale2g_8000_synthetic", "ale2g_8000_noisy_offset"])
func ale2GRecoversIndependentlyEncodedAMD(_ name: String) throws {
    let engine = try ExternalAudioEngine(mode: .ale, settings: .init())
    defer { engine.cancel() }
    try writeALEFixture(name, to: engine)
    let result = try engine.finish()
    #expect(result.text.contains("AMD: \"RADIOWORKBENCH TEST\""))
    #expect(result.records.allSatisfy { $0.decoder == "KiwiSDR ALE 2G" && $0.snrDB == nil })
}

@Test func ale2GPublishesSoundingBeforeClosingLiveInput() async throws {
    let engine = try ExternalAudioEngine(mode: .ale, settings: .init())
    defer { engine.cancel() }
    try writeALEFixture("ale2g_sounding_8000_synthetic", to: engine)
    for _ in 0..<80 {
        if engine.snapshot.text.contains("[From: LAB]") { break }
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(engine.snapshot.text.contains("[Sounding THIS IS] [From: LAB]"))
    _ = try engine.finish()
}

@Test func ale2GSilenceNoiseAndInvalidFloatsDoNotInventMessages() throws {
    let engine = try ExternalAudioEngine(mode: .ale, settings: .init())
    defer { engine.cancel() }
    try engine.write([Float](repeating: 0, count: 80000))
    var noise = [Float](); noise.reserveCapacity(80000)
    var seed: UInt64 = 1029
    for _ in 0..<80000 {
        seed = seed &* 6364136223846793005 &+ 1
        noise.append(Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max) * 0.2)
    }
    try engine.write(noise)
    try engine.write(Array(repeating: [Float.nan, .infinity, -.infinity, 0], count: 16000).flatMap { $0 })
    #expect(try engine.finish().records.isEmpty)
}

private actor ALEUpdateBox {
    var latest: RadioUpdate?
    func receive(_ update: RadioUpdate) { latest = update }
}
@Test func ale2GWorkerProcessesWAVThroughSelectedEngine() async throws {
    let worker = RadioWorker(), box = ALEUpdateBox()
    try await worker.decodeFile(url: aleFixture("ale2g_8000_synthetic"), mode: .ale, settings: .init()) {
        await box.receive($0)
    }
    let update = try #require(await box.latest)
    #expect(update.finished && update.text.contains("RADIOWORKBENCH TEST"))
}
