import AppKit
import Observation
import RadioCore

@MainActor @Observable final class SatDumpOfflineStore {
    var application: URL? = {
        let app = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/SDR/SatDump.app")
        return FileManager.default.fileExists(atPath: app.path) ? app : nil
    }()
    var inputURL: URL?
    var sampleRate = 1_000_000.0
    var format: IQSampleFormat = .cf32
    var frequencyMHz = 137.9
    var capturedAt = Date()
    var captureDateKnown = false
    var pipeline: LRPTPipeline = .k72
    var busy = false
    var log = ""
    var stagePercent: Double?
    var result: SatDumpOfflineResult?
    var lastJobDirectory: URL?
    var status = "Selecciona una grabación I/Q y declara sus parámetros."
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    func prepareSigMF(_ recording: SigMFRecording) {
        guard !busy, let format = recording.satDumpFormat, let capture = recording.captures.first,
              let date = capture.date, let frequency = capture.frequencyHz else {
            error = "Esta captura SigMF no tiene el formato o los metadatos necesarios para SatDump."; return
        }
        inputURL = recording.datasetURL; sampleRate = recording.sampleRate; self.format = format
        frequencyMHz = frequency / 1_000_000; capturedAt = date; captureDateKnown = true
        error = nil; status = "Parámetros importados de SigMF. Confirma que contiene LRPT y pulsa Iniciar para procesar."
    }
    func chooseApplication() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { application = panel.url }
    }
    func chooseInput() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.message = "I/Q crudo intercalado; una grabación WAV de audio de SDR++ no contiene LRPT."
        if panel.runModal() == .OK { inputURL = panel.url }
    }
    func start() {
        guard !busy else { return }
        guard captureDateKnown, let app = application, let inputURL else {
            error = "Selecciona SatDump, un I/Q e indica que conoces la fecha de captura."; return
        }
        let input = SatDumpIQInput(file: inputURL, sampleRate: sampleRate, format: format, centerFrequencyHz: frequencyMHz * 1_000_000, capturedAt: capturedAt, pipeline: pipeline)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RadioWorkbench/SatDumpJobs", isDirectory: true)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        busy = true; error = nil; result = nil; log = ""; stagePercent = nil; lastJobDirectory = directory
        status = "Iniciando SatDump offline; las salidas se guardan en un trabajo nuevo."
        task = Task { [self] in
            defer { busy = false; task = nil }
            do {
                result = try await SatDumpOfflineEngine.run(executable: app.appendingPathComponent("Contents/MacOS/satdump"), input: input, directory: directory) { [weak self] progress in
                    await self?.apply(progress)
                }
                guard let result else { return }
                status = "Proceso terminado · código \(result.exitCode) · \(result.products.count) archivos, \(result.images.count) posibles imágenes. " + (result.images.isEmpty ? "No se obtuvo imagen: revisa señal, formato y registro." : "Revisa los productos antes de utilizarlos.")
            } catch is CancellationError { status = "Trabajo cancelado. Los archivos parciales se conservan en la carpeta del trabajo; no se presentan como productos completos." }
            catch { self.error = error.localizedDescription; status = "El procesamiento no se completó." }
        }
    }
    private func apply(_ progress: SatDumpProgress) { log = progress.log; stagePercent = progress.stagePercent }
    func cancel() { task?.cancel() }
    func showProducts() { if let directory = result?.directory ?? lastJobDirectory { NSWorkspace.shared.activateFileViewerSelecting([directory]) } }
}
