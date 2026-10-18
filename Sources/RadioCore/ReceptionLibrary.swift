import AVFoundation
import CryptoKit
import Foundation

public enum ReceptionSourceKind: String, Codable, CaseIterable, Sendable {
    case audio, iq
    public var title: String { self == .audio ? "Audio" : "I/Q · integración pendiente" }
}

public struct ReceptionRFMetadata: Codable, Equatable, Sendable {
    public var modulation: RFModulation
    public var bandwidthHz: Double
    public var frequencyHz: Double?
    public var sourceDescription: String?
    public var engineVersion: String?
    public init(modulation: RFModulation, bandwidthHz: Double, frequencyHz: Double? = nil,
                sourceDescription: String? = nil, engineVersion: String? = nil) {
        self.modulation = modulation; self.bandwidthHz = bandwidthHz; self.frequencyHz = frequencyHz
        self.sourceDescription = sourceDescription; self.engineVersion = engineVersion
    }
    fileprivate var isValid: Bool {
        bandwidthHz.isFinite && (1...1_000_000_000).contains(bandwidthHz)
            && (frequencyHz.map { $0.isFinite && (1...1_000_000_000_000).contains($0) } ?? true)
            && (sourceDescription?.count ?? 0) <= 300 && (engineVersion?.count ?? 0) <= 200
    }
}

public struct ReceptionAudioMetadata: Codable, Equatable, Sendable {
    public let originalFileName: String
    public let sampleRate: Double
    public let channels: Int
    public let durationSeconds: Double
    public let byteCount: Int64
    public let sha256: String
}

public struct ReceptionSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let mode: RadioMode
    public let settings: DecoderSettings
    public let sourceKind: ReceptionSourceKind
    public let rf: ReceptionRFMetadata
    public let audio: ReceptionAudioMetadata
    public let importedAt: Date
    /// User-supplied capture time, never inferred from import time or file dates.
    public let capturedAt: Date?
    public var trashedAt: Date?
    public let storedFileName: String
    public var isTrashed: Bool { trashedAt != nil }
}

public enum ReceptionLibraryError: LocalizedError {
    case invalidMetadata, invalidAudio, fileTooLarge(Int64), missingAudio, unsafePath, invalidIndex, full, unsupportedSource
    public var errorDescription: String? {
        switch self {
        case .invalidMetadata: "Revisa el nombre, la fecha y los datos de radio de la recepción."
        case .invalidAudio: "El archivo no contiene audio válido que macOS pueda leer."
        case .fileTooLarge(let maximum): "El audio supera el límite de \(ByteCountFormatter.string(fromByteCount: maximum, countStyle: .file)) por recepción."
        case .missingAudio: "Falta el audio guardado de esta recepción. Su ficha se conserva; puedes volver a importar el original."
        case .unsafePath: "La ruta de la biblioteca o del audio no es válida. No se modificó la ficha guardada."
        case .invalidIndex: "No se pudo leer la biblioteca. El índice existente se conserva para poder recuperarlo."
        case .full: "La biblioteca alcanzó el máximo de 1.000 recepciones, incluidas las de la papelera."
        case .unsupportedSource: "Esta ficha corresponde a I/Q. La biblioteca de esta versión abre grabaciones de audio."
        }
    }
}

/// Owns a local index and copies original audio without altering its format.
/// The trash is a reversible metadata state: original audio is never deleted.
public actor ReceptionLibraryRepository {
    public nonisolated let directory: URL
    public nonisolated let maximumAudioBytes: Int64
    private let manager = FileManager.default
    private var sessions: [ReceptionSession] = []
    private var loaded = false
    private let maximumIndexBytes = 10_000_000
    private struct Document: Codable { let schemaVersion: Int; let sessions: [ReceptionSession] }
    private var indexURL: URL { directory.appendingPathComponent("library.json") }
    private var audioDirectory: URL { directory.appendingPathComponent("Audio", isDirectory: true) }

    public init(directory: URL? = nil, maximumAudioBytes: Int64 = 1_073_741_824) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = (directory ?? support.appendingPathComponent("RadioWorkbench/Recepciones", isDirectory: true)).standardizedFileURL
        self.maximumAudioBytes = max(1, maximumAudioBytes)
    }

    public func load() throws -> [ReceptionSession] {
        if loaded { return ordered(sessions) }
        try prepareDirectories()
        guard manager.fileExists(atPath: indexURL.path) else { loaded = true; return [] }
        try requireRegularFile(indexURL)
        let bytes = try boundedIndexData()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let document: Document
        do { document = try decoder.decode(Document.self, from: bytes) }
        catch { throw ReceptionLibraryError.invalidIndex }
        guard document.schemaVersion == 1, document.sessions.count <= 1000,
              Set(document.sessions.map(\.id)).count == document.sessions.count,
              document.sessions.allSatisfy(validSession) else { throw ReceptionLibraryError.invalidIndex }
        sessions = document.sessions; loaded = true
        return ordered(sessions)
    }

    public func importAudio(from source: URL, title: String, mode: RadioMode, settings: DecoderSettings,
                            rf: ReceptionRFMetadata, capturedAt: Date? = nil) throws -> ReceptionSession {
        _ = try load()
        try prepareDirectories()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, rf.isValid,
              capturedAt.map(validDate) ?? true else { throw ReceptionLibraryError.invalidMetadata }
        guard sessions.count < 1000 else { throw ReceptionLibraryError.full }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try requireRegularFile(source)
        let resource = try source.resourceValues(forKeys: [.fileSizeKey])
        if let size = resource.fileSize, Int64(size) > maximumAudioBytes { throw ReceptionLibraryError.fileTooLarge(maximumAudioBytes) }
        let reader: AudioFileReader
        do { reader = try AudioFileReader(url: source); _ = try reader.next() }
        catch { throw ReceptionLibraryError.invalidAudio }
        guard reader.sampleRate.isFinite, (1000...768000).contains(reader.sampleRate),
              (1...64).contains(reader.channelCount), reader.duration.isFinite,
              reader.duration > 0, reader.duration <= 7 * 86400 else { throw ReceptionLibraryError.invalidAudio }
        let originalName = source.lastPathComponent
        guard !originalName.isEmpty, originalName.count <= 255 else { throw ReceptionLibraryError.invalidMetadata }
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
        guard Self.safeExtension(ext) else { throw ReceptionLibraryError.invalidMetadata }
        let id = UUID(), storedName = id.uuidString.lowercased() + "." + ext
        let finalURL = audioDirectory.appendingPathComponent(storedName)
        let staging = audioDirectory.appendingPathComponent(".import-\(id.uuidString).\(ext)")
        var committed = false
        defer {
            try? manager.removeItem(at: staging)
            if !committed { try? manager.removeItem(at: finalURL) }
        }
        let copied = try copyBounded(from: source, to: staging)
        // Probe the actual copied bytes too, in case the source changed while
        // being imported. The library's metadata describes its owned copy.
        let copiedReader: AudioFileReader
        do { copiedReader = try AudioFileReader(url: staging); _ = try copiedReader.next() }
        catch { throw ReceptionLibraryError.invalidAudio }
        let audio = ReceptionAudioMetadata(originalFileName: originalName, sampleRate: copiedReader.sampleRate,
            channels: copiedReader.channelCount, durationSeconds: copiedReader.duration, byteCount: copied.bytes, sha256: copied.sha256)
        let session = ReceptionSession(id: id, title: name, mode: mode, settings: settings, sourceKind: .audio,
            rf: rf, audio: audio, importedAt: Self.seconds(Date()), capturedAt: capturedAt.map(Self.seconds),
            trashedAt: nil, storedFileName: storedName)
        guard validSession(session) else { throw ReceptionLibraryError.invalidMetadata }
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: finalURL)
        let updated = sessions + [session]
        try persist(updated)
        sessions = updated; committed = true
        return session
    }

    public func audioURL(for id: UUID) throws -> URL {
        _ = try load()
        try prepareDirectories()
        guard let session = sessions.first(where: { $0.id == id }), !session.isTrashed else { throw ReceptionLibraryError.missingAudio }
        guard session.sourceKind == .audio else { throw ReceptionLibraryError.unsupportedSource }
        guard validStoredName(session.storedFileName, id: id) else { throw ReceptionLibraryError.unsafePath }
        let url = audioDirectory.appendingPathComponent(session.storedFileName)
        guard manager.fileExists(atPath: url.path) else { throw ReceptionLibraryError.missingAudio }
        try requireRegularFile(url)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size.map(Int64.init) == session.audio.byteCount else { throw ReceptionLibraryError.invalidAudio }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256(), total: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation(); total += Int64(chunk.count)
            guard total <= maximumAudioBytes else { throw ReceptionLibraryError.invalidAudio }
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard total == session.audio.byteCount, digest == session.audio.sha256 else { throw ReceptionLibraryError.invalidAudio }
        return url
    }

    public func trash(id: UUID) throws { try changeTrash(id: id, date: Self.seconds(Date())) }
    public func restore(id: UUID) throws { try changeTrash(id: id, date: nil) }

    private func changeTrash(id: UUID, date: Date?) throws {
        _ = try load()
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw ReceptionLibraryError.invalidMetadata }
        var updated = sessions; updated[index].trashedAt = date
        try persist(updated); sessions = updated
    }
    private func prepareDirectories() throws {
        guard directory.isFileURL else { throw ReceptionLibraryError.unsafePath }
        for url in [directory, audioDirectory] {
            if manager.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, values.isDirectory == true else { throw ReceptionLibraryError.unsafePath }
            } else { try manager.createDirectory(at: url, withIntermediateDirectories: true) }
        }
    }
    private func requireRegularFile(_ url: URL) throws {
        guard url.isFileURL else { throw ReceptionLibraryError.unsafePath }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ReceptionLibraryError.unsafePath }
    }
    private func boundedIndexData() throws -> Data {
        let file = try FileHandle(forReadingFrom: indexURL); defer { try? file.close() }
        let bytes = try file.read(upToCount: maximumIndexBytes + 1) ?? Data()
        guard bytes.count <= maximumIndexBytes else { throw ReceptionLibraryError.invalidIndex }
        return bytes
    }
    private func copyBounded(from source: URL, to target: URL) throws -> (bytes: Int64, sha256: String) {
        guard manager.createFile(atPath: target.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: target)
        defer { try? input.close(); try? output.close() }
        var total: Int64 = 0, hash = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            total += Int64(chunk.count)
            guard total <= maximumAudioBytes else { throw ReceptionLibraryError.fileTooLarge(maximumAudioBytes) }
            hash.update(data: chunk); try output.write(contentsOf: chunk)
        }
        guard total > 0 else { throw ReceptionLibraryError.invalidAudio }
        try output.synchronize()
        return (total, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private func persist(_ updated: [ReceptionSession]) throws {
        try prepareDirectories()
        if manager.fileExists(atPath: indexURL.path) { try requireRegularFile(indexURL) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(Document(schemaVersion: 1, sessions: updated))
        guard bytes.count <= maximumIndexBytes else { throw ReceptionLibraryError.invalidIndex }
        try bytes.write(to: indexURL, options: .atomic)
    }
    private func validSession(_ session: ReceptionSession) -> Bool {
        let audio = session.audio
        return !session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.title.count <= 120
            && session.rf.isValid && validStoredName(session.storedFileName, id: session.id)
            && validDate(session.importedAt) && (session.capturedAt.map(validDate) ?? true) && (session.trashedAt.map(validDate) ?? true)
            && !audio.originalFileName.isEmpty && audio.originalFileName.count <= 255
            && !audio.originalFileName.contains("/") && !audio.originalFileName.contains("\\")
            && audio.sampleRate.isFinite && (1000...768000).contains(audio.sampleRate) && (1...64).contains(audio.channels)
            && audio.durationSeconds.isFinite && audio.durationSeconds > 0 && audio.durationSeconds <= 7 * 86400
            && audio.byteCount > 0 && audio.byteCount <= maximumAudioBytes
            && audio.sha256.count == 64 && audio.sha256.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
    private func validStoredName(_ value: String, id: UUID) -> Bool {
        let prefix = id.uuidString.lowercased() + "."
        return value.hasPrefix(prefix) && Self.safeExtension(String(value.dropFirst(prefix.count)))
    }
    private static func safeExtension(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 10 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    private func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (-62_135_596_800...253_402_300_799).contains(date.timeIntervalSince1970)
    }
    private static func seconds(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }
    private func ordered(_ values: [ReceptionSession]) -> [ReceptionSession] {
        values.sorted { $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt > $1.importedAt }
    }
}
