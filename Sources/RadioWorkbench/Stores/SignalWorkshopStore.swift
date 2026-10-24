import AppKit
import AVFoundation
import Observation
import RadioCore

@MainActor @Observable final class SignalWorkshopStore {
    var reference: SignalReference = .cw
    var referenceProbe: SignalProbeResult?
    var userProbe: SignalProbeResult?
    var userURL: URL?
    var customReferenceURL: URL?
    var referenceChannel: AudioChannelSelection = .mix
    var channel: AudioChannelSelection = .mix
    var busy = false
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<(SignalProbeResult, SignalProbeResult?), Error>?
    @ObservationIgnored private var generation = UUID()

    var referenceURL: URL? { customReferenceURL ?? Bundle.main.url(forResource: reference.fileName, withExtension: "wav", subdirectory: "Examples") }
    var referenceTitle: String { customReferenceURL?.lastPathComponent ?? reference.title }

    func chooseAudio(asReference: Bool = false) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.message = asReference ? "Elige una grabación propia como referencia de comparación." : "Elige la grabación que quieres comparar con la referencia."
        if panel.runModal() == .OK, let url = panel.url {
            stopPlayback()
            if asReference { customReferenceURL = url; referenceChannel = .mix }
            else { userURL = url }
            analyze()
        }
    }
    func useUserAsReference() {
        guard let url = userURL else { return }
        stopPlayback(); customReferenceURL = url; referenceChannel = channel; analyze()
    }
    func restoreLaboratoryReference() {
        stopPlayback(); customReferenceURL = nil; referenceChannel = .mix; analyze()
    }
    func referenceChanged() {
        // A different protocol explicitly returns to its identified laboratory
        // recording, so a custom file cannot inherit a false protocol label.
        restoreLaboratoryReference()
    }
    func analyze() {
        cancelAnalysis()
        guard let referenceURL else { error = "No se encontró la señal de referencia en el paquete."; return }
        let token = UUID(); generation = token
        busy = true; error = nil; referenceProbe = nil; userProbe = nil
        let user = userURL, selectedChannel = channel, selectedReferenceChannel = referenceChannel
        let limit = reference.analysisFrequencyLimit
        let work = Task.detached(priority: .utility) {
            let first = try SignalProbe.analyze(url: referenceURL, channel: selectedReferenceChannel, frequencyLimit: limit)
            try Task.checkCancellation()
            let second = try user.map { try SignalProbe.analyze(url: $0, channel: selectedChannel, frequencyLimit: limit) }
            return (first, second)
        }
        worker = work
        analysisTask = Task {
            do {
                let probes = try await work.value
                guard generation == token, !Task.isCancelled else { return }
                referenceProbe = probes.0; userProbe = probes.1; busy = false; worker = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                busy = false; worker = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func cancelAnalysis() {
        generation = UUID(); analysisTask?.cancel(); worker?.cancel()
        analysisTask = nil; worker = nil; busy = false
    }
    func playReference() { play(referenceURL) }
    func playUser() { play(userURL) }
    private func play(_ url: URL?) {
        guard let url else { return }
        do { player?.stop(); player = try AVAudioPlayer(contentsOf: url); player?.play() }
        catch { self.error = error.localizedDescription }
    }
    func stopPlayback() { player?.stop(); player = nil }
}
