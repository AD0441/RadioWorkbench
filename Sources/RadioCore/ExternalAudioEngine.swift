import Foundation
import Darwin

public enum CWEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual = "Manual", automatic = "CWKit automático", neural = "CWKit neuronal"
    public var id: String { rawValue }
    public static var isSupported: Bool { if #available(macOS 15, *) { true } else { false } }
}
public enum DigitalVoiceProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case dmr = "DMR", p25p1 = "P25 fase I", p25p2 = "P25 fase II", nxdn48 = "NXDN 4800", nxdn96 = "NXDN 9600", dstar = "D-STAR", ysf = "YSF", m17 = "M17", dpmr = "dPMR"
    public var id: String { rawValue }
    public var flag: String {
        switch self { case .dmr: "-fs"; case .p25p1: "-f1"; case .p25p2: "-f2"; case .nxdn48: "-fi"; case .nxdn96: "-fn"; case .dstar: "-fd"; case .ysf: "-fy"; case .m17: "-fz"; case .dpmr: "-fm" }
    }
}
public struct AudioEngineRecord: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public let text: String
    public var frequencyHz: Double?, offsetSeconds: Double?, syncScore: Int?, crcValid: Bool?
    public var tentative: String?, toneHz: Double?, wpm: Double?, snrDB: Double?
    public var slotUTC: Date?
    public var locked: Bool?, confidence: Double?, decoder: String?
    public var dscVariant: String?, eccValid: Bool?, origin: String?, destination: String?
    public var rxChannel: Int?, txChannel: Int?, symbolErrors: Int?, interpretation: String?, symbols: [Int]?
    private enum CodingKeys: String, CodingKey {
        case dscVariant = "variant", eccValid = "ecc_ok", rxChannel = "rx_channel", txChannel = "tx_channel", symbolErrors = "symbol_errors"
        case origin, destination, interpretation, symbols
        case text, frequencyHz, offsetSeconds, syncScore, crcValid, tentative, toneHz, wpm, snrDB, slotUTC, locked, confidence, decoder }
    public var monitorLine: String {
        if let frequencyHz, let offsetSeconds { return String(format: "%.0f Hz · Δt %+.2f s · %@", frequencyHz, offsetSeconds, text) }
        return text
    }
}
public struct ExternalEngineSnapshot: Sendable {
    public var text: String
    public var records: [AudioEngineRecord]
    public var detail: String
}
public enum AudioEngineError: LocalizedError {
    case unavailable(String), failed(String)
    public var errorDescription: String? { switch self { case .unavailable(let s), .failed(let s): s } }
}
private final class EngineOutput: @unchecked Sendable {
    let lock = NSLock(), eof = DispatchSemaphore(value: 0), errorEOF = DispatchSemaphore(value: 0)
    var pending = Data(), records: [AudioEngineRecord] = [], text = "", detail = ""
    func ingest(_ data: Data, json: Bool) {
        lock.lock(); defer { lock.unlock() }
        if !json { text = String((text + String(decoding: data, as: UTF8.self)).suffix(40000)); return }
        pending.append(data)
        if pending.count > 262144 { pending.removeAll(); detail = "Respuesta del motor demasiado grande"; return }
        while let end = pending.firstIndex(of: 10) {
            if let record = try? JSONDecoder().decode(AudioEngineRecord.self, from: pending.prefix(upTo: end)) {
                records.append(record); if records.count > 200 { records.removeFirst(records.count - 200) }
                text = String((text + record.text + (record.dscVariant == nil ? "" : "\n")).suffix(40000))
            }
            pending.removeSubrange(...end)
        }
    }
    func log(_ data: Data) { lock.lock(); defer { lock.unlock() }; detail = String((detail + String(decoding: data, as: UTF8.self)).suffix(4096)) }
    func snapshot() -> ExternalEngineSnapshot { lock.lock(); defer { lock.unlock() }; return .init(text: text, records: records, detail: detail) }
}
/// PCM transport runs on the worker, never on the CoreAudio callback. All output is bounded.
public final class ExternalAudioEngine: @unchecked Sendable {
    private let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
    private let collector = EngineOutput(), ended = DispatchSemaphore(value: 0), lock = NSLock()
    private var closed = false
    private let int16Input: Bool
    public let voiceURL: URL?
    public init(mode: RadioMode, settings: DecoderSettings, executableURL: URL? = nil, voiceURL: URL? = nil) throws {
        int16Input = mode == .digitalVoice || mode == .gmdss; self.voiceURL = voiceURL
        let name: String, args: [String], override: String
        if mode == .ft8 || mode == .ft4 { name = "ftx-helper"; args = [mode.rawValue]; override = "FTX_HELPER_PATH" }
        else if mode == .gmdss {
            name = "dsc-helper"; override = "DSC_HELPER_PATH"
            args = ["--variant", settings.dscVariant.rawValue, "--rate", "48000", "--center-hz", String(settings.frequency)] + (settings.inverted ? ["--inverted"] : []) + (settings.dscDeemphasized ? ["--deemphasized"] : [])
        }
        else if mode == .mt63 {
            try settings.validated(sampleRate: 8000, mode: mode)
            name = "mt63-helper"; override = "MT63_HELPER_PATH"
            args = ["--bandwidth", String(settings.mt63Variant.bandwidth), "--interleave", settings.mt63Variant.interleave, "--center-hz", String(settings.frequency)]
        } else if mode == .ale {
            name = "ale-helper"; override = "ALE_HELPER_PATH"; args = []
        }
        else if mode == .morse && settings.cwEngine != .manual {
            guard CWEngine.isSupported else { throw AudioEngineError.unavailable("CWKit requiere macOS 15. Elige Morse manual en este Mac.") }
            name = "cw-helper"; override = "CW_HELPER_PATH"
            let model = ProcessInfo.processInfo.environment["CW_MODEL_PATH"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.url(forResource: "CWNet", withExtension: "mlmodelc")
            args = [settings.cwEngine == .neural ? "neural" : "classic"] + (model.map { ["--model", $0.path] } ?? [])
        } else if mode == .digitalVoice {
            guard Self.dsdSupported else { throw AudioEngineError.unavailable("El paquete oficial DSD-neo 2.10.0 requiere macOS 26.") }
            name = "dsd-neo"; override = "DSD_NEO_PATH"
            args = ["--frontend", "none", "-Z", settings.digitalVoiceProtocol.flag, "-i", "-", "-s", "48000", "-o", "null"] + (voiceURL.map { ["-w", $0.path] } ?? [])
        } else { throw RadioError.unsupportedMode }
        let envURL = ProcessInfo.processInfo.environment[override].map { URL(fileURLWithPath: $0) }
        let installed = mode == .digitalVoice ? Self.dsdInstalledURL : nil
        guard let url = executableURL ?? envURL ?? installed ?? Bundle.main.url(forAuxiliaryExecutable: name), FileManager.default.isExecutableFile(atPath: url.path) else {
            throw AudioEngineError.unavailable(mode == .digitalVoice ? "Descarga DSD-neo con el botón del receptor antes de iniciar." : "Falta el motor \(name). Abre la app empaquetada.")
        }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = url; process.arguments = args
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        if mode == .digitalVoice {
            var env = ProcessInfo.processInfo.environment
            env["DYLD_FALLBACK_LIBRARY_PATH"] = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib").path
            process.environment = env
        }
        let collector = collector, ended = ended, json = mode != .digitalVoice
        process.terminationHandler = { _ in ended.signal() }
        output.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; collector.eof.signal() } else { collector.ingest(d, json: json) }
        }
        errors.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; collector.errorEOF.signal() } else if json { collector.log(d) } else { collector.ingest(d, json: false) }
        }
        do { try process.run() } catch { output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil; throw error }
    }
    public static var dsdSupported: Bool { if #available(macOS 26, *) { true } else { false } }
    public static var dsdInstalledURL: URL? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = root.appendingPathComponent("RadioWorkbench/Engines/dsd-neo-2.10.0/bin/dsd-neo")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    public var snapshot: ExternalEngineSnapshot { collector.snapshot() }
    public func write(_ samples: [Float]) throws {
        guard process.isRunning else { throw AudioEngineError.failed("El motor terminó: " + snapshot.text + snapshot.detail) }
        let data: Data
        if int16Input { data = samples.map { Int16(max(-1, min(1, $0.isFinite ? $0 : 0)) * 32767) }.withUnsafeBytes { Data($0) } }
        else { data = samples.withUnsafeBytes { Data($0) } }
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func close() { lock.lock(); defer { lock.unlock() }; if !closed { closed = true; try? input.fileHandleForWriting.close() } }
    public func finish() throws -> ExternalEngineSnapshot {
        close()
        guard ended.wait(timeout: .now() + 25) == .success else { cancel(); throw AudioEngineError.failed("El motor superó el tiempo de espera.") }
        _ = collector.eof.wait(timeout: .now() + 2)
        _ = collector.errorEOF.wait(timeout: .now() + 2)
        guard process.terminationStatus == 0 else { throw AudioEngineError.failed(snapshot.detail + snapshot.text) }
        return snapshot
    }
    public func cancel() { close(); if process.isRunning { process.terminate() } }
    public func finishVoice() { close(); if ended.wait(timeout: .now() + 2) != .success { cancel() } }
    deinit { cancel(); output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil }
}
