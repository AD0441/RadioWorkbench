import Foundation

public struct ACARSProcessSnapshot: Sendable {
    public let messages: [ACARSMessage]
    public let total: Int
    public let invalidLines: Int
    public let queueDrops: Int
    public let diagnostics: String
    public var text: String { messages.map(\.monitorLine).joined(separator: "\n") }
    public var status: String { "acarsdec · MSK 2400 baud · \(total) mensajes validados" + (invalidLines == 0 ? "" : " · \(invalidLines) respuestas inválidas") + (queueDrops == 0 ? "" : " · \(queueDrops) descartados en la cola") }
}

private final class ACARSCollector: @unchecked Sendable {
    // Every mutable field is protected by the lock; pipe callbacks never touch UI.
    private let lock = NSLock()
    private var pending = Data()
    private var messages: [ACARSMessage] = []
    private var total = 0, invalid = 0, queueDrops = 0, diagnostics = ""
    let eof = DispatchSemaphore(value: 0)
    func ingest(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        if pending.count > 65536 { pending.removeAll(keepingCapacity: true); invalid += 1; return }
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            if !line.isEmpty {
                let event = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                if let dropped = event?["queueDrops"] as? Int { queueDrops = max(queueDrops, dropped) }
                if event?["event"] as? String == "summary" {
                    // A terminal metrics record, not an aircraft message.
                } else if let message = try? JSONDecoder().decode(ACARSMessage.self, from: line) {
                    messages.append(message); total += 1
                    messages.sort { $0.timestamp < $1.timestamp }
                    if messages.count > 200 { messages.removeFirst(messages.count - 200) }
                } else { invalid += 1 }
            }
            pending.removeSubrange(...newline)
        }
    }
    func log(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        diagnostics = String((diagnostics + String(decoding: data, as: UTF8.self)).suffix(4096))
    }
    func snapshot() -> ACARSProcessSnapshot {
        lock.lock(); defer { lock.unlock() }
        return ACARSProcessSnapshot(messages: messages, total: total, invalidLines: invalid, queueDrops: queueDrops, diagnostics: diagnostics)
    }
}

public final class ACARSProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let collector = ACARSCollector()
    private let terminated = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var inputClosed = false
    public init(executableURL: URL? = nil) throws {
        let override = ProcessInfo.processInfo.environment["ACARS_HELPER_PATH"].map { URL(fileURLWithPath: $0) }
        guard let url = executableURL ?? override ?? Bundle.main.url(forAuxiliaryExecutable: "acars-helper"),
              FileManager.default.isExecutableFile(atPath: url.path) else { throw RadioError.acarsEngineUnavailable }
        process.executableURL = url
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        let finished = terminated, collector = collector
        process.terminationHandler = { _ in finished.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            if let data = try? handle.read(upToCount: 8192), !data.isEmpty { collector.ingest(data) }
            else { handle.readabilityHandler = nil; collector.eof.signal() }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            if let data = try? handle.read(upToCount: 4096), !data.isEmpty { collector.log(data) }
            else { handle.readabilityHandler = nil }
        }
        do { try process.run() }
        catch { output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil; throw error }
    }
    public func write(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        let bytes = samples.withUnsafeBytes { Data($0) }
        try input.fileHandleForWriting.write(contentsOf: bytes)
    }
    public var snapshot: ACARSProcessSnapshot { collector.snapshot() }
    public var isRunning: Bool { process.isRunning }
    public func finish() throws -> ACARSProcessSnapshot {
        closeInput()
        guard terminated.wait(timeout: .now() + 5) == .success else { cancel(); throw RadioError.acarsEngineFailed("El motor no terminó a tiempo.") }
        _ = collector.eof.wait(timeout: .now() + 2)
        guard process.terminationStatus == 0 else { throw RadioError.acarsEngineFailed(snapshot.diagnostics.isEmpty ? "El motor terminó inesperadamente." : snapshot.diagnostics) }
        return snapshot
    }
    private func closeInput() {
        lock.lock(); defer { lock.unlock() }
        if !inputClosed { inputClosed = true; try? input.fileHandleForWriting.close() }
    }
    public func cancel() {
        closeInput()
        if process.isRunning { process.terminate() }
    }
    deinit {
        cancel()
        output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
        try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
    }
}
