import AppKit
import AVFoundation
import Foundation

// Opt-in local hardware probe. It runs through the same store/tap/decoder as
// Escuchar. A separate explicit --diagnostic-wav flag records bounded PCM.
@MainActor enum MicrophoneDiagnostic {
    private struct Snapshot: Encodable {
        let elapsed: Double
        let live: Bool
        let permission: String
        let source: String
        let sampleRate: Double
        let channels: Int
        let audioCenterHz: Double
        let clockPPM: Double
        let robot36Compatibility: Bool
        let samples: UInt64
        let dropped: UInt64
        let levelDBFS: Double?
        let clipped: Bool
        let status: String
        let decoderStatus: String
        let imageCaption: String
        let imageWidth: Int?
        let imageHeight: Int?
        let error: String?
    }
    private struct Report: Encodable {
        let version = "0.8.0"
        let started: Date
        var finished = false
        var snapshots: [Snapshot] = []
    }

    static func runIfRequested(receiver: ReceiverStore) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--sstv-microphone-test"), !receiver.microphoneDiagnosticStarted,
              let index = arguments.firstIndex(of: "--diagnostics-path"), index + 1 < arguments.count else { return }
        receiver.microphoneDiagnosticStarted = true
        let url = URL(fileURLWithPath: arguments[index + 1])
        let requested = arguments.firstIndex(of: "--probe-seconds").flatMap {
            $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil
        } ?? 15
        let duration = min(300, max(5, requested))
        var report = Report(started: Date())
        let started = ProcessInfo.processInfo.systemUptime
        if receiver.prepareSSTVMicrophone() {
            if arguments.contains("--robot36c-compatibility") {
                receiver.settings.sstvFormat = .robot36; receiver.settings.sstvRobot36Compatibility = true
            }
            if let index = arguments.firstIndex(of: "--audio-center"), index + 1 < arguments.count,
               let center = Double(arguments[index + 1]), center.isFinite, (1000...2500).contains(center) {
                receiver.settings.frequency = center
            }
            if let index = arguments.firstIndex(of: "--clock-ppm"), index + 1 < arguments.count,
               let ppm = Double(arguments[index + 1]), ppm.isFinite, (-50000...50000).contains(ppm) {
                receiver.settings.imageClockPPM = ppm
            }
            receiver.startLive()
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        var exportedImage = false
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for tick in 0...duration {
                try Task.checkCancellation()
                let permission = switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: "authorized"
                case .notDetermined: "notDetermined"
                case .denied: "denied"
                case .restricted: "restricted"
                @unknown default: "unknown"
                }
                report.snapshots.append(Snapshot(
                    elapsed: ProcessInfo.processInfo.systemUptime - started, live: receiver.live,
                    permission: permission, source: receiver.source, sampleRate: receiver.captureSampleRate,
                    channels: receiver.sourceChannelCount, audioCenterHz: receiver.settings.frequency,
                    clockPPM: receiver.settings.imageClockPPM, robot36Compatibility: receiver.settings.sstvRobot36Compatibility,
                    samples: receiver.samplesReceived,
                    dropped: receiver.dropped, levelDBFS: receiver.frame?.levelDB, clipped: receiver.frame?.clipped ?? false,
                    status: receiver.detail, decoderStatus: String(receiver.text.prefix(512)), imageCaption: receiver.imageCaption,
                    imageWidth: receiver.receivedImage?.width, imageHeight: receiver.receivedImage?.height, error: receiver.error))
                if !exportedImage, receiver.imageCaption.contains("imagen completa"), let image = receiver.receivedImage,
                   let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try png.write(to: url.deletingPathExtension().appendingPathExtension("png"), options: .atomic)
                    exportedImage = true
                }
                if tick == duration || receiver.error != nil { receiver.stop(); report.finished = true }
                try encoder.encode(report).write(to: url, options: .atomic)
                if report.finished { break }
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            receiver.stop()
            receiver.error = "No se pudo completar el diagnóstico local: \(error.localizedDescription)"
        }
    }
}
