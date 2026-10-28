import Foundation
import Darwin

/// FLEX frame metadata emitted by the bundled helper. Symbol rate is not bit rate
/// for 4-FSK. Fragments remain separate records; no reassembly is implied.
public struct FLEXMetadata: Codable, Sendable, Equatable {
    public let symbolRate: Int
    public let levels: Int
    public let phase: String
    public let cycle: Int
    public let frame: Int
    public let fragment: String?
}

public struct MultimonRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let decoder: String
    public let address: Int?
    public let function: Int?
    public let kind: String
    public let body: String
    public let flex: FLEXMetadata?
    init(id: UUID, decoder: String, address: Int?, function: Int?, kind: String, body: String, flex: FLEXMetadata? = nil) {
        self.id = id; self.decoder = decoder; self.address = address; self.function = function
        self.kind = kind; self.body = body; self.flex = flex
    }
    public var monitorLine: String {
        "\(decoder)" + (address.map { " · capcode \($0)" } ?? "") + (function.map { " · F\($0)" } ?? "") + (flex.map { " · \($0.symbolRate) Bd/\($0.levels)-FSK · fase \($0.phase) · \($0.cycle).\($0.frame)" } ?? "") + " · \(kind): \(body)"
    }
    static func parse(_ data: Data, mode: RadioMode, standard: FiveToneStandard) -> Self? {
        guard data.count <= 16_384 else { return nil }
        if mode == .flex {
            struct Event: Decodable {
                let demod_name: String, sync_baud: Int, sync_level: Int, phase_number: String
                let cycle_number: Int, frame_number: Int, capcode: Int
                let message: String?, tone: String?, tone_long: String?, fragment_flag: String?
            }
            guard let row = try? JSONDecoder().decode(Event.self, from: data),
                  [1600, 3200].contains(row.sync_baud), [2, 4].contains(row.sync_level),
                  (0...14).contains(row.cycle_number), (0...127).contains(row.frame_number),
                  (1...1_933_312).contains(row.capcode) else { return nil }
            // Only phases carried by each FLEX modulation are meaningful.
            let phases = row.sync_baud == 1600 ? (row.sync_level == 2 ? ["A"] : ["A", "B"])
                : (row.sync_level == 2 ? ["A", "C"] : ["A", "B", "C", "D"])
            guard phases.contains(row.phase_number) else { return nil }
            let kind: String, text: String
            switch row.demod_name {
            case "flex_alphanumeric":
                guard let message = row.message, let fragment = row.fragment_flag,
                      ["K", "C", "F"].contains(fragment), row.tone == nil, row.tone_long == nil else { return nil }
                kind = fragment == "K" ? "ALPHA" : "ALPHA · fragmento \(fragment)"
                text = message
            case "flex_numeric":
                guard let message = row.message, !message.isEmpty,
                      message.allSatisfy({ "0123456789 U-][".contains($0) }),
                      row.tone == nil, row.tone_long == nil, row.fragment_flag == nil else { return nil }
                kind = "NUMERIC"; text = message
            case "flex_tone_only":
                guard row.message == nil, row.fragment_flag == nil else { return nil }
                let digits = (row.tone ?? "") + (row.tone_long ?? "")
                guard digits.count <= 16, digits.allSatisfy({ "0123456789 U-][".contains($0) }) else { return nil }
                kind = "TONO"; text = digits.isEmpty ? "Aviso sin texto" : digits
            default: return nil // Unsupported binary/secure/group/long-address records are not messages.
            }
            guard text.utf8.count <= 1_024,
                  text.unicodeScalars.allSatisfy({ $0.value >= 32 || [9, 10, 13].contains($0.value) }) else { return nil }
            return Self(id: UUID(), decoder: "FLEX", address: row.capcode, function: nil, kind: kind, body: text,
                        flex: FLEXMetadata(symbolRate: row.sync_baud, levels: row.sync_level, phase: row.phase_number,
                                           cycle: row.cycle_number, frame: row.frame_number, fragment: row.fragment_flag))
        }
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
    private var discardingLine = false
    let eof = DispatchSemaphore(value: 0)
    init(mode: RadioMode, standard: FiveToneStandard) { self.mode = mode; self.standard = standard }
    func ingest(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        var remaining = data[...]
        while !remaining.isEmpty {
            let end = remaining.firstIndex(of: 10)
            let piece = remaining.prefix(upTo: end ?? remaining.endIndex)
            if !discardingLine {
                if pending.count + piece.count <= 16_384 { pending.append(contentsOf: piece) }
                else { pending.removeAll(keepingCapacity: true); discardingLine = true; invalid += 1 }
            }
            if let end {
                if !discardingLine { consumeLine() }
                discardingLine = false
                remaining = remaining[remaining.index(after: end)...]
            } else { break }
        }
    }
    private func consumeLine() {
        guard !pending.isEmpty else { return }
        if let record = MultimonRecord.parse(pending, mode: mode, standard: standard) {
            records.append(record); total += 1
            if records.count > 200 { records.removeFirst(records.count - 200) }
        } else { invalid += 1 }
        pending.removeAll(keepingCapacity: true)
    }
    func finishOutput() {
        lock.lock(); defer { lock.unlock() }
        if !discardingLine { consumeLine() }
        eof.signal()
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
    private var inputClosed = false, cancellationScheduled = false
    public init(mode: RadioMode, settings: DecoderSettings, executableURL: URL? = nil) throws {
        guard mode.isMultimon, (mode != .pocsag || (0...2).contains(settings.pagerCorrectionBits)) else { throw RadioError.unsupportedMode }
        let override = ProcessInfo.processInfo.environment["MULTIMON_HELPER_PATH"].map { URL(fileURLWithPath: $0) }
        guard let url = executableURL ?? override ?? Bundle.main.url(forAuxiliaryExecutable: "multimon-helper"),
            FileManager.default.isExecutableFile(atPath: url.path) else { throw RadioError.multimonEngineUnavailable }
        collector = MultimonCollector(mode: mode, standard: settings.fiveToneStandard)
        process.executableURL = url
        var arguments = ["-q", "-c", "-t", "raw"]
        for demodulator in mode == .pocsag ? settings.pagerRate.demodulators : mode == .flex ? ["FLEX"] : [settings.fiveToneStandard.rawValue] { arguments += ["-a", demodulator] }
        if mode == .pocsag {
            arguments += ["--json", "-b", String(settings.pagerCorrectionBits), "-P", "auto"]
            if !settings.pagerShowEmpty { arguments.append("-e") }
        }
        if mode == .flex { arguments.append("--json") }
        arguments.append("-"); process.arguments = arguments
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        let signal = terminated, collector = collector
        process.terminationHandler = { _ in signal.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            // A live pipe can contain a single short JSON event. Read what is
            // available now rather than waiting for 8192 bytes or EOF.
            let data = handle.availableData
            if !data.isEmpty { collector.ingest(data) }
            else { handle.readabilityHandler = nil; collector.finishOutput() }
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
    public func cancel() {
        closeInput()
        lock.lock()
        let schedule = !cancellationScheduled
        cancellationScheduled = true
        lock.unlock()
        guard schedule else { return }
        let child = process
        if child.isRunning { child.terminate() }
        // Termination is cooperative; a malformed helper can ignore SIGTERM.
        // Escalate only this owned process, never a name or a process group.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
        }
    }
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
