import CryptoKit
import Foundation
import Testing
@testable import RadioCore

private func receptionFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-reception-tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func receptionFixture() throws -> URL {
    try #require(Bundle.module.url(forResource: "morse_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
}
private func receptionRF() -> ReceptionRFMetadata {
    .init(modulation: .usb, bandwidthHz: 2400, frequencyHz: 7_100_000,
          sourceDescription: "Audio sintético de prueba", engineVersion: "RadioWorkbench · prueba")
}

@Test func receptionLibraryOwnsOriginalAudioAndRoundTripsAllSettings() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("original.wav")
    let original = try Data(contentsOf: receptionFixture()); try original.write(to: source)
    let root = folder.appendingPathComponent("Library")
    let repository = ReceptionLibraryRepository(directory: root)
    var settings = DecoderSettings(); settings.frequency = 725; settings.wordsPerMinute = 25
    settings.inverted = true; settings.audioChannel = .channel(0); settings.sstvRobot36Compatibility = true
    let item = try await repository.importAudio(from: source, title: "  Prueba CW  ", mode: .morse,
                                               settings: settings, rf: receptionRF())
    #expect(item.title == "Prueba CW" && item.capturedAt == nil && item.sourceKind == .audio)
    #expect(item.audio.sampleRate == 8000 && item.audio.channels == 1 && item.audio.durationSeconds > 0)
    #expect(item.audio.sha256 == SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined())
    #expect(item.audio.byteCount == original.count)
    try FileManager.default.removeItem(at: source)
    let savedURL = try await repository.audioURL(for: item.id)
    #expect(try Data(contentsOf: savedURL) == original)
    let reloaded = try await ReceptionLibraryRepository(directory: root).load()
    #expect(reloaded == [item])
    #expect(reloaded.first?.settings == settings && reloaded.first?.rf == receptionRF())
    let index = try String(contentsOf: root.appendingPathComponent("library.json"), encoding: .utf8)
    #expect(index.contains("Z\"")) // Stored date is UTC, independently of the Mac's time zone.
    #expect(!index.contains(source.path)) // Full external paths are not persisted.
}

@Test func receptionLibraryCaptureTimeIsExplicitAndTrashIsRecoverable() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let capture = Date(timeIntervalSince1970: 1_600_000_000)
    let repository = ReceptionLibraryRepository(directory: folder)
    let item = try await repository.importAudio(from: receptionFixture(), title: "Fecha conocida", mode: .morse,
        settings: .init(), rf: receptionRF(), capturedAt: capture)
    #expect(item.capturedAt == capture && item.importedAt > capture)
    let saved = try await repository.audioURL(for: item.id)
    try await repository.trash(id: item.id)
    #expect(FileManager.default.fileExists(atPath: saved.path))
    #expect(try await repository.load().first?.isTrashed == true)
    await #expect(throws: ReceptionLibraryError.self) { try await repository.audioURL(for: item.id) }
    try await repository.restore(id: item.id)
    #expect(try await repository.audioURL(for: item.id) == saved)
    #expect(try await ReceptionLibraryRepository(directory: folder).load().first?.isTrashed == false)
}

@Test func receptionLibraryRejectsOversizeAndBadAudioWithoutChangingSnapshot() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let bytes = try Data(contentsOf: receptionFixture())
    let root = folder.appendingPathComponent("Library")
    let repository = ReceptionLibraryRepository(directory: root, maximumAudioBytes: Int64(bytes.count))
    let item = try await repository.importAudio(from: receptionFixture(), title: "Conservada", mode: .morse,
                                               settings: .init(), rf: receptionRF())
    let snapshot = try Data(contentsOf: root.appendingPathComponent("library.json"))
    let oversized = folder.appendingPathComponent("demasiado.wav")
    try (bytes + Data(repeating: 0, count: 64)).write(to: oversized)
    await #expect(throws: ReceptionLibraryError.self) {
        try await repository.importAudio(from: oversized, title: "Grande", mode: .morse, settings: .init(), rf: receptionRF())
    }
    let invalid = folder.appendingPathComponent("roto.wav"); try Data("No contiene audio".utf8).write(to: invalid)
    await #expect(throws: ReceptionLibraryError.self) {
        try await repository.importAudio(from: invalid, title: "Roto", mode: .morse, settings: .init(), rf: receptionRF())
    }
    #expect(try Data(contentsOf: root.appendingPathComponent("library.json")) == snapshot)
    #expect(try await repository.load() == [item])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Audio").path).count == 1)
}

@Test func receptionLibraryPreservesMetadataWhenAudioIsMissing() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let repository = ReceptionLibraryRepository(directory: folder)
    let item = try await repository.importAudio(from: receptionFixture(), title: "Audio ausente", mode: .morse,
                                               settings: .init(), rf: receptionRF())
    try FileManager.default.removeItem(at: await repository.audioURL(for: item.id))
    await #expect(throws: ReceptionLibraryError.self) { try await repository.audioURL(for: item.id) }
    #expect(try await repository.load().first?.id == item.id)
    try await repository.trash(id: item.id); try await repository.restore(id: item.id)
    #expect(try await repository.load().first?.isTrashed == false)
}

@Test func receptionLibraryRejectsIndexTraversalAndPreservesOriginalIndex() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let repository = ReceptionLibraryRepository(directory: folder)
    _ = try await repository.importAudio(from: receptionFixture(), title: "Ficha", mode: .morse,
                                         settings: .init(), rf: receptionRF())
    let index = folder.appendingPathComponent("library.json")
    var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
    var records = try #require(json["sessions"] as? [[String: Any]])
    records[0]["storedFileName"] = "../../outside.wav"; json["sessions"] = records
    let malicious = try JSONSerialization.data(withJSONObject: json); try malicious.write(to: index)
    let reopened = ReceptionLibraryRepository(directory: folder)
    await #expect(throws: ReceptionLibraryError.self) { try await reopened.load() }
    await #expect(throws: ReceptionLibraryError.self) {
        try await reopened.importAudio(from: receptionFixture(), title: "Nueva", mode: .morse, settings: .init(), rf: receptionRF())
    }
    #expect(try Data(contentsOf: index) == malicious)
}

@Test func receptionLibraryRejectsSymlinkedOwnedAudio() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let repository = ReceptionLibraryRepository(directory: folder.appendingPathComponent("Library"))
    let item = try await repository.importAudio(from: receptionFixture(), title: "Ficha", mode: .morse,
                                               settings: .init(), rf: receptionRF())
    let owned = try await repository.audioURL(for: item.id)
    let outside = folder.appendingPathComponent("outside.wav")
    try FileManager.default.copyItem(at: receptionFixture(), to: outside)
    try FileManager.default.removeItem(at: owned)
    try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: outside)
    await #expect(throws: ReceptionLibraryError.self) { try await repository.audioURL(for: item.id) }
    #expect(try Data(contentsOf: outside) == Data(contentsOf: receptionFixture()))
}

@Test func receptionLibraryCleansUncommittedCopyIfIndexCannotBeWritten() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let repository = ReceptionLibraryRepository(directory: folder)
    #expect(try await repository.load().isEmpty)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("library.json"), withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) {
        try await repository.importAudio(from: receptionFixture(), title: "No se publica", mode: .morse, settings: .init(), rf: receptionRF())
    }
    #expect(try await repository.load().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Audio").path).isEmpty)
}

@Test func receptionLibrarySerializesConcurrentImports() async throws {
    let folder = try receptionFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let repository = ReceptionLibraryRepository(directory: folder)
    let source = try receptionFixture(), rf = receptionRF()
    async let first = repository.importAudio(from: source, title: "Una", mode: .morse, settings: .init(), rf: rf)
    async let second = repository.importAudio(from: source, title: "Dos", mode: .morse, settings: .init(), rf: rf)
    let results = try await [first, second]
    #expect(Set(results.map(\.id)).count == 2)
    #expect(try await ReceptionLibraryRepository(directory: folder).load().count == 2)
}

@Test func receptionLibraryDetectsSameSizeAudioTamperingBeforeRedecoding() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = try #require(Bundle.module.url(forResource: "morse_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let repository = ReceptionLibraryRepository(directory: folder)
    let item = try await repository.importAudio(from: source, title: "Checksum", mode: .morse, settings: .init(), rf: .init(modulation: .usb, bandwidthHz: 2400))
    let audio = try await repository.audioURL(for: item.id)
    var bytes = try Data(contentsOf: audio); bytes[bytes.count - 1] ^= 1
    try bytes.write(to: audio)
    await #expect(throws: ReceptionLibraryError.self) { try await repository.audioURL(for: item.id) }
    #expect(try await repository.load().count == 1)
}
