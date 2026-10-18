import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private actor NetworkWorkerResult {
    var final: RadioUpdate?
    func receive(_ value: RadioUpdate) { if value.finished { final = value } }
}

@Test func networkAudioEOFDrainsAndFinalizesNativeDecoder() async throws {
    let url = try #require(Bundle.module.url(forResource: "packet_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url), ring = try AudioSampleRing(capacity: 1_000_000)
    while let samples = try reader.next() { ring.writeMono(samples) }
    ring.finish()
    var settings = DecoderSettings(); settings.frequency = 1700
    let result = NetworkWorkerResult()
    try await RadioWorker().decodeLive(ring: ring, sampleRate: reader.sampleRate, mode: .packet, settings: settings, source: "TCP sintético") { await result.receive($0) }
    let final = try #require(await result.final)
    #expect(final.text.contains("TEST-1>APRS"))
    #expect(final.finished && final.dropped == 0)
    var remaining = [Float](repeating: 0, count: 16)
    #expect(ring.read(into: &remaining) == 0)
}

@Test func networkRingEOFIsOnlyDrainedAfterTheFinalPublishedSamples() async throws {
    let ring = try AudioSampleRing(capacity: 20000)
    let producer = Task.detached {
        for index in 0..<1000 { ring.writeMono([Float](repeating: Float(index), count: 10)) }
        ring.finish()
    }
    var storage = [Float](repeating: 0, count: 137), received: [Float] = []
    while true {
        let count = ring.read(into: &storage)
        if count > 0 { received.append(contentsOf: storage.prefix(count)) }
        if count == 0 && ring.isDrained { break }
        await Task.yield()
    }
    await producer.value
    #expect(received.count == 10000 && received.last == 999 && ring.dropped == 0)
    #expect(received.enumerated().allSatisfy { $0.element == Float($0.offset / 10) })
}
