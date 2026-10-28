import Foundation
import CryptoKit
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func sigFixture(_ directory: URL, change: ([String: Any]) -> [String: Any] = { $0 }) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = Data((0..<128).map(UInt8.init))
    try data.write(to: directory.appendingPathComponent("sample.sigmf-data"))
    let global: [String: Any] = ["core:datatype": "ci16_le", "core:sample_rate": 48_000,
        "core:version": "1.2.6", "core:sha512": SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()]
    let document: [String: Any] = ["global": global,
        "captures": [["core:sample_start": 0, "core:frequency": 137_100_000, "core:datetime": "2026-10-25T12:00:00.000Z"]],
        "annotations": [["core:sample_start": 2, "core:sample_count": 8, "core:comment": "keep me"]]]
    let url = directory.appendingPathComponent("sample.sigmf-meta")
    try JSONSerialization.data(withJSONObject: change(document)).write(to: url)
    return url
}
private func temporaryQualityDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("rwb-quality-\(UUID())") }

@Test func sigMFRoundTripPreservesSamplesAnnotationsAndTrash() async throws {
    let root = temporaryQualityDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let original = try sigFixture(root.appendingPathComponent("source"))
    let sourceBytes = try Data(contentsOf: original)
    let recording = try SigMF.inspect(metadataURL: original)
    #expect(recording.sampleCount == 32)
    #expect(recording.duration == 32.0 / 48_000)
    #expect(recording.satDumpFormat == .cs16)
    #expect(recording.captures.first?.date == Date(timeIntervalSince1970: 1_792_929_600))
    let library = SigMFLibrary(directory: root.appendingPathComponent("library"))
    let entry = try await library.importRecording(metadata: original)
    let exported = try await library.exportRecording(id: entry.id, to: root)
    let meta = exported.appendingPathComponent("recording.sigmf-meta")
    let exportedRecording = try SigMF.inspect(metadataURL: meta)
    #expect(try Data(contentsOf: exportedRecording.datasetURL) == Data(contentsOf: recording.datasetURL))
    let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: meta)) as? [String: Any])
    #expect((json["annotations"] as? [[String: Any]])?.first?["core:comment"] as? String == "keep me")
    #expect(try Data(contentsOf: original) == sourceBytes)
    try await library.setTrashed(id: entry.id, trashed: true)
    await #expect(throws: SigMFError.self) { try await library.recording(id: entry.id) }
    try await library.setTrashed(id: entry.id, trashed: false)
    #expect(try await library.recording(id: entry.id).expectedSHA512 == entry.sha512)
    let reloaded = SigMFLibrary(directory: root.appendingPathComponent("library"))
    #expect(try await reloaded.load().count == 1)
}

@Test(arguments: ["../outside", "misaligned", "header", "required-extension", "capture", "version"])
func sigMFRejectsUnsupportedOrInvalidLayout(_ variant: String) throws {
    let root = temporaryQualityDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let metadata = try sigFixture(root) { document in
        var document = document, global = document["global"] as! [String: Any]
        switch variant {
        case "../outside": global["core:dataset"] = "../outside.sigmf-data"
        case "header": global["core:offset"] = 16
        case "required-extension": global["core:extensions"] = [["name": "unknown", "version": "1.0.0", "optional": false]]
        case "capture": document["captures"] = [["core:sample_start": 32]]
        case "version": global["core:version"] = "2.0.0"
        default: break
        }
        document["global"] = global; return document
    }
    if variant == "misaligned" { try Data([0, 1, 2]).write(to: root.appendingPathComponent("sample.sigmf-data")) }
    #expect(throws: SigMFError.self) { try SigMF.inspect(metadataURL: metadata) }
}

@Test func sigMFChecksumFailureRollsBackAndSymlinksAreRejected() async throws {
    let root = temporaryQualityDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let metadata = try sigFixture(root.appendingPathComponent("source"))
    let samples = metadata.deletingLastPathComponent().appendingPathComponent("sample.sigmf-data")
    try Data(repeating: 0, count: 128).write(to: samples)
    let library = SigMFLibrary(directory: root.appendingPathComponent("library"))
    await #expect(throws: SigMFError.self) { try await library.importRecording(metadata: metadata) }
    #expect(try await library.load().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).isEmpty)
    let outside = root.appendingPathComponent("outside")
    try FileManager.default.moveItem(at: samples, to: outside)
    try FileManager.default.createSymbolicLink(at: samples, withDestinationURL: outside)
    #expect(throws: SigMFError.self) { try SigMF.inspect(metadataURL: metadata) }
}

@Test func sigMFCorruptIndexIsPreserved() async throws {
    let root = temporaryQualityDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let bytes = Data("broken index".utf8), index = root.appendingPathComponent("index.json")
    try bytes.write(to: index)
    await #expect(throws: SigMFError.self) { try await SigMFLibrary(directory: root).load() }
    #expect(try Data(contentsOf: index) == bytes)
}

@Test @MainActor func sigMFPreparesSatDumpWithoutStartingAProcess() throws {
    let root = temporaryQualityDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let recording = try SigMF.inspect(metadataURL: sigFixture(root))
    let store = SatDumpOfflineStore()
    store.prepareSigMF(recording)
    #expect(store.inputURL == recording.datasetURL)
    #expect(store.sampleRate == 48_000)
    #expect(store.format == .cs16)
    #expect(!store.busy)
}

@Test func updateFeedRejectsInsecureOrUnusableConfigurations() {
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    #expect(UpdateFeedConfiguration(feed: "https://example.org/feed.xml", publicKey: key) != nil)
    #expect(UpdateFeedConfiguration(feed: "http://example.org/feed.xml", publicKey: key) == nil)
    #expect(UpdateFeedConfiguration(feed: "https://user:password@example.org/feed.xml", publicKey: key) == nil)
    #expect(UpdateFeedConfiguration(feed: "file:///tmp/feed.xml", publicKey: key) == nil)
    #expect(UpdateFeedConfiguration(feed: "https://example.org/feed.xml", publicKey: "bad") == nil)
    #expect(UpdateFeedConfiguration(feed: nil, publicKey: key) == nil)
}

@Test func decoderComparisonUsesTheSamePacketAudioAndReportsCRC() async throws {
    let url = try #require(Bundle.module.url(forResource: "packet_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    var a = DecoderSettings(); a.frequency = 1700
    var b = a; b.frequency = 3000
    let result = try await DecoderComparison().compare(url: url, mode: .packet, a: a, b: b)
    #expect(result.a.integrity?.accepted == 1)
    #expect(result.b.integrity?.accepted == 0)
    #expect(!result.a.text.isEmpty)
    #expect(result.audioSeconds > 0)
    #expect(result.a.settings.frequency == 1700)
    #expect(result.b.settings.frequency == 3000)
}

@Test func decoderComparisonCancellationAndUnsupportedMode() async throws {
    let worker = DecoderComparison(), settings = DecoderSettings(), url = URL(fileURLWithPath: "/does-not-exist.wav")
    await #expect(throws: DecoderComparisonError.self) { try await worker.compare(url: url, mode: .digitalVoice, a: settings, b: settings) }
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        return try await worker.compare(url: url, mode: .packet, a: settings, b: settings)
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}
