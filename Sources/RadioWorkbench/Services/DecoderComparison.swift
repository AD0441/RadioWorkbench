import Foundation
import RadioCore

struct DecoderComparisonResult: Sendable {
    struct Run: Sendable {
        let settings: DecoderSettings
        let seconds: Double
        let text: String
        let integrity: ReceptionIntegrity?
        let retainedRecords: Int
    }
    let mode: RadioMode
    let audioSeconds: Double
    let a: Run
    let b: Run
}

enum DecoderComparisonError: LocalizedError {
    case unsupported, tooLarge, incomplete
    var errorDescription: String? {
        switch self {
        case .unsupported: "El comparador A/B admite los modos de texto disponibles. Voz e imágenes requieren una evaluación específica."
        case .tooLarge: "Elige audio de hasta diez minutos y 1 GB para esta comparación."
        case .incomplete: "El motor no terminó la decodificación; no se publicó una comparación parcial."
        }
    }
}

actor DecoderComparison {
    static func supports(_ mode: RadioMode) -> Bool { mode.isAudioAvailable && !mode.isImage && mode != .digitalVoice }
    private actor Output {
        var final: RadioUpdate?
        func accept(_ update: RadioUpdate) { if update.finished { final = update } }
    }
    func compare(url: URL, mode: RadioMode, a: DecoderSettings, b: DecoderSettings) async throws -> DecoderComparisonResult {
        try Task.checkCancellation()
        guard Self.supports(mode) else { throw DecoderComparisonError.unsupported }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 1_000_000_000 else { throw DecoderComparisonError.tooLarge }
        let reader = try AudioFileReader(url: url)
        let duration = reader.duration
        guard duration.isFinite, duration <= 600 else { throw DecoderComparisonError.tooLarge }
        try a.validated(sampleRate: reader.sampleRate, mode: mode)
        try b.validated(sampleRate: reader.sampleRate, mode: mode)
        // Sequential runs avoid competition for the same CPU or external helper.
        let first = try await run(url, mode: mode, settings: a)
        try Task.checkCancellation()
        let second = try await run(url, mode: mode, settings: b)
        try Task.checkCancellation()
        return .init(mode: mode, audioSeconds: duration, a: first, b: second)
    }
    private func run(_ url: URL, mode: RadioMode, settings: DecoderSettings) async throws -> DecoderComparisonResult.Run {
        let output = Output(), started = ProcessInfo.processInfo.systemUptime
        try await RadioWorker().decodeFile(url: url, mode: mode, settings: settings) { await output.accept($0) }
        guard let result = await output.final else { throw DecoderComparisonError.incomplete }
        return .init(settings: settings, seconds: ProcessInfo.processInfo.systemUptime - started,
            text: String(result.text.suffix(32_000)), integrity: result.integrity,
            retainedRecords: result.acarsMessages.count + result.multimonRecords.count + result.engineRecords.count)
    }
}
