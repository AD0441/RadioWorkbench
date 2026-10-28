import CryptoKit
import Foundation

public enum SigMFError: LocalizedError {
    case invalidMetadata, unsupportedLayout, missingDataset, invalidDataset, checksumMismatch, libraryCorrupt
    public var errorDescription: String? {
        switch self {
        case .invalidMetadata: "SigMF: metadatos incompletos o fuera de rango (se admite la especificación 1.0–1.2)."
        case .unsupportedLayout: "SigMF: esta entrada usa cabeceras, desplazamientos, datos externos o extensiones obligatorias que aún no se admiten."
        case .missingDataset: "SigMF: falta el archivo de muestras junto a los metadatos. Selecciona el par original, sin enlaces simbólicos."
        case .invalidDataset: "SigMF: tamaño o estructura de muestras inválidos; máximo 100 GB y tramas completas."
        case .checksumMismatch: "SigMF: el SHA-512 de las muestras no coincide con el declarado. No se importó la grabación."
        case .libraryCorrupt: "El índice I/Q no es válido. Se conservan sus archivos; no se sobrescribió el índice."
        }
    }
}

public struct SigMFCapture: Codable, Equatable, Sendable {
    public let sampleStart: UInt64
    public let frequencyHz: Double?
    public let date: Date?
}

public struct SigMFRecording: Sendable {
    public let metadataURL: URL, datasetURL: URL
    public let datatype: String
    public let sampleRate: Double
    public let channels: Int
    public let byteCount: Int64
    public let sampleCount: UInt64
    public let captures: [SigMFCapture]
    public let description: String
    public let expectedSHA512: String?
    let metadataJSON: Data
    public var duration: Double { Double(sampleCount) / sampleRate }
    public var isComplex: Bool { datatype.hasPrefix("c") }
    /// SatDump's raw single-channel input needs one uninterrupted capture.
    public var satDumpFormat: IQSampleFormat? {
        guard channels == 1, captures.count == 1, captures[0].sampleStart == 0 else { return nil }
        switch datatype { case "cf32_le": return .cf32; case "ci16_le": return .cs16; case "cu8": return .cu8; case "ci8": return .cs8; default: return nil }
    }
}

public enum SigMF {
    public static let maximumDatasetBytes: Int64 = 100_000_000_000
    private struct Document: Decodable {
        struct Global: Decodable {
            let datatype: String, version: String
            let sampleRate: Double
            let channels: Int?
            let dataset: String?, sha512: String?, description: String?
            let offset: UInt64?, trailingBytes: UInt64?, metadataOnly: Bool?
            let extensions: [ExtensionInfo]?
            enum CodingKeys: String, CodingKey {
                case datatype = "core:datatype", version = "core:version", sampleRate = "core:sample_rate", channels = "core:num_channels"
                case dataset = "core:dataset", sha512 = "core:sha512", description = "core:description", offset = "core:offset"
                case trailingBytes = "core:trailing_bytes", metadataOnly = "core:metadata_only", extensions = "core:extensions"
            }
        }
        struct ExtensionInfo: Decodable { let name: String; let optional: Bool }
        struct Capture: Decodable {
            let sampleStart: UInt64
            let frequency: Double?, datetime: String?
            let headerBytes: UInt64?
            enum CodingKeys: String, CodingKey {
                case sampleStart = "core:sample_start", frequency = "core:frequency", datetime = "core:datetime", headerBytes = "core:header_bytes"
            }
        }
        let global: Global
        let captures: [Capture]
    }
    public static func inspect(metadataURL: URL) throws -> SigMFRecording {
        guard metadataURL.isFileURL, metadataURL.pathExtension == "sigmf-meta" else { throw SigMFError.invalidMetadata }
        let info = try metadataURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, let count = info.fileSize, (1...1_048_576).contains(count) else { throw SigMFError.invalidMetadata }
        let bytes = try Data(contentsOf: metadataURL)
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: bytes) } catch { throw SigMFError.invalidMetadata }
        let g = document.global, channels = document.global.channels ?? 1
        let components = g.version.split(separator: ".", omittingEmptySubsequences: false)
        let version = components.compactMap { Int($0) }
        guard components.count == 3, version.count == 3, version[2] >= 0, version[0] == 1, (0...2).contains(version[1]),
              g.sampleRate.isFinite, (1...100_000_000).contains(g.sampleRate), (1...32).contains(channels),
              document.captures.count <= 4096, let sampleBytes = bytesPerSample(g.datatype) else { throw SigMFError.invalidMetadata }
        guard (g.offset ?? 0) == 0, (g.trailingBytes ?? 0) == 0, g.metadataOnly != true,
              !(g.extensions ?? []).contains(where: { !$0.optional }),
              document.captures.allSatisfy({ ($0.headerBytes ?? 0) == 0 }) else { throw SigMFError.unsupportedLayout }
        let filename = g.dataset ?? metadataURL.deletingPathExtension().lastPathComponent + ".sigmf-data"
        guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/"), !filename.contains("\\"),
              !filename.contains("\0"), filename.utf8.count <= 255 else { throw SigMFError.unsupportedLayout }
        let dataset = metadataURL.deletingLastPathComponent().appendingPathComponent(filename)
        let file: URLResourceValues
        do { file = try dataset.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) } catch { throw SigMFError.missingDataset }
        guard file.isRegularFile == true, file.isSymbolicLink != true else { throw SigMFError.missingDataset }
        let length = Int64(file.fileSize ?? 0), stride = Int64(sampleBytes * channels)
        guard length > 0, length <= maximumDatasetBytes, length % stride == 0 else { throw SigMFError.invalidDataset }
        let samples = UInt64(length / stride)
        var captures: [SigMFCapture] = [], previous: UInt64?
        for capture in document.captures {
            guard capture.sampleStart < samples, previous.map({ capture.sampleStart > $0 }) ?? true,
                  capture.frequency.map({ $0.isFinite && (0...1_000_000_000_000).contains($0) }) ?? true else { throw SigMFError.invalidMetadata }
            let date = try capture.datetime.map { value -> Date in
                let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = precise.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { throw SigMFError.invalidMetadata }
                return date
            }
            captures.append(.init(sampleStart: capture.sampleStart, frequencyHz: capture.frequency, date: date)); previous = capture.sampleStart
        }
        if let hash = g.sha512, hash.count != 128 || !hash.allSatisfy(\.isHexDigit) { throw SigMFError.invalidMetadata }
        return SigMFRecording(metadataURL: metadataURL, datasetURL: dataset, datatype: g.datatype, sampleRate: g.sampleRate,
            channels: channels, byteCount: length, sampleCount: samples, captures: captures,
            description: String((g.description ?? "").prefix(4096)), expectedSHA512: g.sha512?.lowercased(), metadataJSON: bytes)
    }
    public static func bytesPerSample(_ datatype: String) -> Int? {
        switch datatype {
        case "cu8", "ci8": 2
        case "ru8", "ri8": 1
        case "ci16_le", "ci16_be", "cu16_le", "cu16_be": 4
        case "ri16_le", "ri16_be", "ru16_le", "ru16_be": 2
        case "cf32_le", "cf32_be", "ci32_le", "ci32_be", "cu32_le", "cu32_be": 8
        case "rf32_le", "rf32_be", "ri32_le", "ri32_be", "ru32_le", "ru32_be": 4
        case "cf64_le", "cf64_be": 16
        case "rf64_le", "rf64_be": 8
        default: nil
        }
    }
    static func archivedMetadata(_ recording: SigMFRecording, sha512: String) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: recording.metadataJSON) as? [String: Any],
              var global = object["global"] as? [String: Any] else { throw SigMFError.invalidMetadata }
        global["core:dataset"] = "recording.sigmf-data"; global["core:sha512"] = sha512
        object["global"] = global
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

public struct SigMFLibraryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let datatype: String
    public let sampleRate: Double
    public let channels: Int
    public let byteCount: Int64
    public let duration: Double
    public let importedAt: Date
    public let sha512: String
    public var trashed = false
}

public actor SigMFLibrary {
    public nonisolated let directory: URL
    private var entries: [SigMFLibraryEntry] = []
    private var loaded = false
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench/SigMF", isDirectory: true)
    }
    private var index: URL { directory.appendingPathComponent("index.json") }
    public func load() throws -> [SigMFLibraryEntry] {
        if loaded { return entries }
        if FileManager.default.fileExists(atPath: index.path) {
            guard (try index.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw SigMFError.libraryCorrupt }
            do {
                let values = try JSONDecoder().decode([SigMFLibraryEntry].self, from: Data(contentsOf: index))
                guard values.count <= 1000, Set(values.map(\.id)).count == values.count,
                      values.allSatisfy({ SigMF.bytesPerSample($0.datatype) != nil && $0.sampleRate.isFinite && $0.sampleRate > 0 && $0.duration.isFinite && $0.duration > 0 && (1...32).contains($0.channels) && (1...SigMF.maximumDatasetBytes).contains($0.byteCount) && $0.sha512.count == 128 && $0.sha512.allSatisfy(\.isHexDigit) }) else { throw SigMFError.libraryCorrupt }
                entries = values
            } catch { throw SigMFError.libraryCorrupt }
        }
        loaded = true; return entries
    }
    public func importRecording(metadata: URL) throws -> SigMFLibraryEntry {
        _ = try load(); guard entries.count < 1000 else { throw SigMFError.libraryCorrupt }
        let recording = try SigMF.inspect(metadataURL: metadata), id = UUID()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".import-\(id)"), final = directory.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging); try? FileManager.default.removeItem(at: final) } }
        let hash = try copyDataset(recording.datasetURL, to: staging.appendingPathComponent("recording.sigmf-data"), expectedBytes: recording.byteCount)
        if let expected = recording.expectedSHA512, hash != expected { throw SigMFError.checksumMismatch }
        try SigMF.archivedMetadata(recording, sha512: hash).write(to: staging.appendingPathComponent("recording.sigmf-meta"), options: .atomic)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: final)
        let entry = SigMFLibraryEntry(id: id, name: metadata.deletingPathExtension().lastPathComponent, datatype: recording.datatype,
            sampleRate: recording.sampleRate, channels: recording.channels, byteCount: recording.byteCount,
            duration: recording.duration, importedAt: Date(), sha512: hash)
        try persist(entries + [entry]); committed = true; return entry
    }
    public func recording(id: UUID) throws -> SigMFRecording {
        _ = try load(); guard entries.contains(where: { $0.id == id && !$0.trashed }) else { throw SigMFError.missingDataset }
        return try SigMF.inspect(metadataURL: directory.appendingPathComponent(id.uuidString).appendingPathComponent("recording.sigmf-meta"))
    }
    public func exportRecording(id: UUID, to parent: URL) throws -> URL {
        let recording = try recording(id: id)
        let target = parent.appendingPathComponent("RadioWorkbench-IQ-\(id.uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: target) } }
        let hash = try copyDataset(recording.datasetURL, to: target.appendingPathComponent("recording.sigmf-data"), expectedBytes: recording.byteCount)
        guard hash == recording.expectedSHA512 else { throw SigMFError.checksumMismatch }
        try SigMF.archivedMetadata(recording, sha512: hash).write(to: target.appendingPathComponent("recording.sigmf-meta"), options: .atomic)
        committed = true; return target
    }
    public func setTrashed(id: UUID, trashed: Bool) throws {
        _ = try load(); var values = entries
        guard let position = values.firstIndex(where: { $0.id == id }) else { return }
        values[position].trashed = trashed; try persist(values)
    }
    private func persist(_ values: [SigMFLibraryEntry]) throws {
        try JSONEncoder().encode(values).write(to: index, options: .atomic); entries = values
    }
    private func copyDataset(_ source: URL, to target: URL, expectedBytes: Int64) throws -> String {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw SigMFError.invalidDataset }
        let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
        var count: Int64 = 0, hash = SHA512()
        while let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation(); count += Int64(bytes.count)
            guard count <= expectedBytes else { throw SigMFError.invalidDataset }
            hash.update(data: bytes); try output.write(contentsOf: bytes)
        }
        guard count == expectedBytes else { throw SigMFError.invalidDataset }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
