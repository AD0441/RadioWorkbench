import AppKit
import Foundation
import RadioCore

// Opt-in file regression through the normal store/worker, without starting mic.
@MainActor enum FileReceptionDiagnostic {
    private struct Report: Encodable {
        let version = "0.12.0"
        let source: String
        let caption: String
        let width: Int?
        let height: Int?
        let manualClockPPM: Double
        let automatic: Bool
        let reduction: SSTVNoiseReduction
        let calibration: SSTVCalibration?
        let error: String?
    }
    static func runIfRequested(receiver: ReceiverStore) async {
        let args = ProcessInfo.processInfo.arguments
        guard let inputIndex = args.firstIndex(of: "--sstv-file-test"), inputIndex + 1 < args.count,
              let outputIndex = args.firstIndex(of: "--file-diagnostics-path"), outputIndex + 1 < args.count else { return }
        let output = URL(fileURLWithPath: args[outputIndex + 1])
        receiver.select(.sstv); receiver.settings.frequency = 1900; receiver.settings.imageClockPPM = 0
        receiver.settings.imageAutoSync = true; receiver.settings.imageStartSeconds = 0; receiver.settings.sstvAutoCalibrate = true
        receiver.settings.threshold = 0.001; receiver.settings.audioChannel = .mix
        if args.contains("--robot36c-compatibility") { receiver.settings.sstvFormat = .martinM4; receiver.settings.sstvRobot36Compatibility = true }
        receiver.decode(URL(fileURLWithPath: args[inputIndex + 1]))
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + 120
            while receiver.busy, ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(100)) }
            if receiver.busy { receiver.stop(); receiver.error = "La prueba del archivo excedió 120 segundos." }
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let report = Report(source: receiver.source, caption: receiver.imageCaption,
                width: receiver.receivedImage?.width, height: receiver.receivedImage?.height,
                manualClockPPM: receiver.settings.imageClockPPM, automatic: receiver.settings.sstvAutoCalibrate,
                reduction: receiver.settings.sstvNoiseReduction, calibration: receiver.sstvCalibration, error: receiver.error)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: output, options: .atomic)
            if let image = receiver.receivedImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try png.write(to: output.deletingPathExtension().appendingPathExtension("png"), options: .atomic)
            }
        } catch { receiver.error = "No se pudo guardar el diagnóstico del archivo: \(error.localizedDescription)" }
    }
}
