import AppKit
import AVFoundation
import Observation
import RadioCore

@MainActor @Observable final class SignalWorkshopStore {
    var reference: SignalReference = .cw
    var referenceProbe: SignalProbeResult?
    var userProbe: SignalProbeResult?
    var userURL: URL?
    var channel: AudioChannelSelection = .mix
    var busy = false
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    var referenceURL: URL? { Bundle.main.url(forResource: reference.fileName, withExtension: "wav", subdirectory: "Examples") }
    func chooseAudio() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { userURL = panel.url; analyze() }
    }
    func analyze() {
        guard !busy else { return }
        guard let referenceURL else { error = "No se encontró la señal de referencia en el paquete."; return }
        busy = true; error = nil; referenceProbe = nil; userProbe = nil
        let user = userURL, selectedChannel = channel
        Task {
            defer { busy = false }
            do {
                let probes = try await Task.detached(priority: .utility) {
                    (try SignalProbe.analyze(url: referenceURL), try user.map { try SignalProbe.analyze(url: $0, channel: selectedChannel) })
                }.value
                referenceProbe = probes.0; userProbe = probes.1
            } catch { self.error = error.localizedDescription }
        }
    }
    func playReference() {
        guard let url = referenceURL else { return }
        do { player?.stop(); player = try AVAudioPlayer(contentsOf: url); player?.play() }
        catch { self.error = error.localizedDescription }
    }
    func stopPlayback() { player?.stop() }
}
