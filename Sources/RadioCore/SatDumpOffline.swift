import Foundation
import Darwin

public enum IQSampleFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case cf32, cs16, cs8, cu8
    public var id: String { rawValue }
    public var bytesPerFrame: Int { switch self { case .cf32: 8; case .cs16: 4; case .cs8, .cu8: 2 } }
}
public enum LRPTPipeline: String, CaseIterable, Codable, Sendable, Identifiable {
    case k72 = "meteor_m2-x_lrpt", k80 = "meteor_m2-x_lrpt_80k"
    public var id: String { rawValue }
    public var title: String { self == .k72 ? "METEOR M2-X · 72 ksímbolos/s" : "METEOR M2-X · 80 ksímbolos/s" }
}
public struct SatDumpIQInput: Codable, Sendable {
    public let file: URL
    public let sampleRate: Double
    public let format: IQSampleFormat
    public let centerFrequencyHz: Double
    public let capturedAt: Date
    public let pipeline: LRPTPipeline
    public init(file: URL, sampleRate: Double, format: IQSampleFormat, centerFrequencyHz: Double, capturedAt: Date, pipeline: LRPTPipeline) {
        self.file = file; self.sampleRate = sampleRate; self.format = format
        self.centerFrequencyHz = centerFrequencyHz; self.capturedAt = capturedAt; self.pipeline = pipeline
    }
    public func validated() throws -> Int64 {
        guard file.isFileURL, sampleRate.isFinite, (192000...10_000_000).contains(sampleRate),
              centerFrequencyHz.isFinite, (1_000_000...20_000_000_000).contains(centerFrequencyHz),
              capturedAt.timeIntervalSince1970.isFinite, capturedAt >= Date(timeIntervalSince1970: 0), capturedAt <= Date().addingTimeInterval(300) else { throw SatDumpOfflineError.invalidInput }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 100_000_000_000, size % format.bytesPerFrame == 0 else { throw SatDumpOfflineError.invalidInput }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let head = try handle.read(upToCount: 4) ?? Data()
        guard head != Data("RIFF".utf8), head != Data("RF64".utf8) else { throw SatDumpOfflineError.invalidInput }
        return Int64(size)
    }
    public func arguments(output: URL, tle: URL) -> [String] {
        [pipeline.rawValue, "baseband", file.path, output.path, "--samplerate", String(sampleRate), "--baseband_format", format.rawValue,
         "--start_timestamp", String(capturedAt.timeIntervalSince1970), "--year_override", String(BroadcastCalendar.utc.component(.year, from: capturedAt)),
         "--tle_override", tle.path]
    }
}
public struct SatDumpProgress: Sendable { public let log: String; public let stagePercent: Double? }
public struct SatDumpOfflineResult: Sendable {
    public let directory: URL
    public let products: [URL]
    public let exitCode: Int32
    public let log: String
    public var images: [URL] { products.filter { ["png", "jpg", "jpeg", "tif", "tiff"].contains($0.pathExtension.lowercased()) } }
}
public enum SatDumpOfflineError: LocalizedError {
    case invalidInput, unavailable, unsafeOutput, timeout
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Selecciona I/Q crudo intercalado y declara formato, tasa 192 kHz–10 MHz, frecuencia y fecha de captura. WAV de audio no es una entrada LRPT. Límite: 100 GB."
        case .unavailable: "Selecciona SatDump.app con su ejecutable de consola. El aislamiento offline de macOS también debe estar disponible."
        case .unsafeOutput: "No se pudo preparar una carpeta nueva y segura para este trabajo."
        case .timeout: "SatDump superó el límite de dos horas; el trabajo se detuvo."
        }
    }
}

private final class SatDumpProcess: @unchecked Sendable {
    let process = Process(), pipe = Pipe(), lock = NSLock()
    private var log = ""
    private var cancellationRequested = false
    func read(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        log = String((log + text).suffix(32768))
    }
    var snapshot: SatDumpProgress {
        lock.lock(); defer { lock.unlock() }
        // SatDump 1.2.3 may emit inf or enormous percentages for empty input.
        let pattern = #"Progress\s+([^\s%]+)%"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: log, range: NSRange(log.startIndex..., in: log))
        let percent = matches.last.flatMap { match -> Double? in
            guard let range = Range(match.range(at: 1), in: log), let n = Double(log[range]), n.isFinite, (0...100).contains(n) else { return nil }
            return n
        }
        return .init(log: log, stagePercent: percent)
    }
    func cancel() {
        lock.lock()
        let shouldCancel = !cancellationRequested && process.isRunning
        cancellationRequested = true
        lock.unlock()
        guard shouldCancel else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    deinit { pipe.fileHandleForReading.readabilityHandler = nil }
}

public enum SatDumpOfflineEngine {
    /// Executes only the selected CLI, with network denied and all writes
    /// restricted to this new job. It never starts SatDump's GUI or SDR inputs.
    public static func run(executable: URL, input: SatDumpIQInput, directory: URL,
                           progress: @escaping @Sendable (SatDumpProgress) async -> Void) async throws -> SatDumpOfflineResult {
        try Task.checkCancellation()
        _ = try input.validated()
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: executable.path), manager.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { throw SatDumpOfflineError.unavailable }
        guard directory.isFileURL, !manager.fileExists(atPath: directory.path) else { throw SatDumpOfflineError.unsafeOutput }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("Products", isDirectory: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let tle = directory.appendingPathComponent("offline-empty.tle")
        try Data().write(to: tle, options: .atomic)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(input).write(to: directory.appendingPathComponent("iq-input.json"), options: .atomic)
        guard let physicalPath = realpath(directory.path, nil) else { throw SatDumpOfflineError.unsafeOutput }
        let physicalDirectory = String(cString: physicalPath); free(physicalPath)
        let pathEncoder = JSONEncoder(); pathEncoder.outputFormatting = [.withoutEscapingSlashes]
        let literal = String(decoding: try pathEncoder.encode(physicalDirectory), as: UTF8.self)
        let profile = "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath \(literal)))"
        let runner = SatDumpProcess(), process = runner.process
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", profile, executable.path] + input.arguments(output: output, tle: tle)
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = runner.pipe; process.standardError = runner.pipe
        runner.pipe.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil } else { runner.read(bytes) }
        }
        defer { runner.cancel(); runner.pipe.fileHandleForReading.readabilityHandler = nil }
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 7200
        return try await withTaskCancellationHandler {
            while process.isRunning {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime >= deadline { runner.cancel(); throw SatDumpOfflineError.timeout }
                await progress(runner.snapshot)
                try await Task.sleep(for: .milliseconds(300))
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
            let snapshot = runner.snapshot
            try snapshot.log.write(to: directory.appendingPathComponent("satdump.log"), atomically: true, encoding: .utf8)
            let products = try collectProducts(output)
            await progress(snapshot)
            return .init(directory: directory, products: products.sorted { $0.path < $1.path }, exitCode: process.terminationStatus, log: snapshot.log)
        } onCancel: { runner.cancel() }
    }
    private static func collectProducts(_ output: URL) throws -> [URL] {
        var products: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: output, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let file as URL in enumerator {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { continue }
                products.append(file)
                if products.count >= 1000 { break }
            }
        }
        return products
    }

}
