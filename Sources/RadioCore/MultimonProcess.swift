import Foundation

public struct MultimonRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let decoder: String
    public let address: Int?
    public let function: Int?
    public let kind: String
    public let body: String
    public var monitorLine: String {
        "\(decoder)" + (address.map { " · capcode \($0)" } ?? "") + (function.map { " · F\($0)" } ?? "") + " · \(kind): \(body)"
    }
    static func parse(_ data: Data, mode: RadioMode, standard: FiveToneStandard) -> Self? {
        if mode == .pocsag {
            struct Event: Decodable { let demod_name: String, address: Int, function: Int; let alpha: String?, numeric: String?, skyper: String? }
            guard let row = try? JSONDecoder().decode(Event.self, from: data),
                ["POCSAG512", "POCSAG1200", "POCSAG2400"].contains(row.demod_name),
                (0..<2_097_152).contains(row.address), (0...3).contains(row.function) else { return nil }
            let key = row.alpha != nil ? "ALPHA" : row.numeric != nil ? "NUMERIC" : row.skyper != nil ? "SKYPER" : "TONO"
            let text = row.alpha ?? row.numeric ?? row.skyper ?? "Aviso sin texto"
            guard text.utf8.count <= 8_192 else { return nil }
            return Self(id: UUID(), decoder: row.demod_name, address: row.address, function: row.function, kind: key, body: text)
        }
        guard let line = String(data: data, encoding: .utf8), let colon = line.firstIndex(of: ":"),
            String(line[..<colon]) == standard.rawValue else { return nil }
        let body = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(body.count), body.allSatisfy({ "0123456789ABCDEF".contains($0) }) else { return nil }
        return Self(id: UUID(), decoder: standard.rawValue, address: nil, function: nil, kind: "SECUENCIA", body: body)
    }
}
public struct MultimonSnapshot: Sendable {
    public let records: [MultimonRecord]
    public let total: Int, invalidLines: Int
    public let diagnostics: String
    public var text: String { records.map(\.monitorLine).joined(separator: "\n") }
    public var status: String { "multimon-ng · \(total) registros · PCM 22050 Hz" + (invalidLines > 0 ? " · \(invalidLines) salidas descartadas" : "") }
}
private final class MultimonCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let mode: RadioMode, standard: FiveToneStandard
    private var pending = Data(), records: [MultimonRecord] = []
    private var total = 0, invalid = 0, diagnostics = ""
    let eof = DispatchSemaphore(value: 0)
    init(mode: RadioMode, standard: FiveToneStandard) { self.mode = mode; self.standard = standard }
    func ingest(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        if pending.count > 65_536 { pending.removeAll(keepingCapacity: true); invalid += 1; return }
        while let end = pending.firstIndex(of: 10) {
            let line = Data(pending.prefix(upTo: end))
            if !line.isEmpty {
                if let record = MultimonRecord.parse(line, mode: mode, standard: standard) {
                    records.append(record); total += 1
                    if records.count > 200 { records.removeFirst(records.count - 200) }
                } else { invalid += 1 }
            }
            pending.removeSubrange(...end)
        }
    }
    func log(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        diagnostics = String((diagnostics + String(decoding: data, as: UTF8.self)).suffix(4_096))
    }
    func snapshot() -> MultimonSnapshot {
        lock.lock(); defer { lock.unlock() }
        return MultimonSnapshot(records: records, total: total, invalidLines: invalid, diagnostics: diagnostics)
    }
}
public final class MultimonProcess: @unchecked Sendable {
    private let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
    private let collector: MultimonCollector
    private let terminated = DispatchSemaphore(value: 0), lock = NSLock()
    private var inputClosed = false
    public init(mode: RadioMode, settings: DecoderSettings, executableURL: URL? = nil) throws {
        guard mode.isMultimon, (0...2).contains(settings.pagerCorrectionBits) else { throw RadioError.unsupportedMode }
        let override = ProcessInfo.processInfo.environment["MULTIMON_HELPER_PATH"].map { URL(fileURLWithPath: $0) }
        guard let url = executableURL ?? override ?? Bundle.main.url(forAuxiliaryExecutable: "multimon-helper"),
            FileManager.default.isExecutableFile(atPath: url.path) else { throw RadioError.multimonEngineUnavailable }
        collector = MultimonCollector(mode: mode, standard: settings.fiveToneStandard)
        process.executableURL = url
        var arguments = ["-q", "-c", "-t", "raw"]
        for demodulator in mode == .pocsag ? settings.pagerRate.demodulators : [settings.fiveToneStandard.rawValue] { arguments += ["-a", demodulator] }
        if mode == .pocsag {
            arguments += ["--json", "-b", String(settings.pagerCorrectionBits), "-P", "auto"]
            if !settings.pagerShowEmpty { arguments.append("-e") }
        }
        arguments.append("-"); process.arguments = arguments
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        let signal = terminated, collector = collector
        process.terminationHandler = { _ in signal.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            // A live pipe can contain a single short JSON event. Read what is
            // available now rather than waiting for 8192 bytes or EOF.
            let data = handle.availableData
            if !data.isEmpty { collector.ingest(data) }
            else { handle.readabilityHandler = nil; collector.eof.signal() }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.log(data) }
            else { handle.readabilityHandler = nil }
        }
        do { try process.run() }
        catch { output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil; throw error }
    }
    public var isRunning: Bool { process.isRunning }
    public var snapshot: MultimonSnapshot { collector.snapshot() }
    public func write(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        guard isRunning else { throw RadioError.multimonEngineFailed(snapshot.diagnostics) }
        let pcm = samples.map { value -> Int16 in
            let finite = value.isFinite ? value : 0
            return Int16((max(-1, min(32_767.0 / 32_768, finite)) * 32_768).rounded()).littleEndian
        }
        try pcm.withUnsafeBytes { try input.fileHandleForWriting.write(contentsOf: Data($0)) }
    }
    private func closeInput() {
        lock.lock(); defer { lock.unlock() }
        if !inputClosed { inputClosed = true; try? input.fileHandleForWriting.close() }
    }
    public func cancel() { closeInput(); if process.isRunning { process.terminate() } }
    public func finish() throws -> MultimonSnapshot {
        closeInput()
        guard terminated.wait(timeout: .now() + 5) == .success else { cancel(); throw RadioError.multimonEngineFailed("El motor no terminó a tiempo.") }
        guard collector.eof.wait(timeout: .now() + 2) == .success, process.terminationStatus == 0 else { throw RadioError.multimonEngineFailed(snapshot.diagnostics) }
        return snapshot
    }
    deinit {
        cancel(); output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
        try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
    }
}
