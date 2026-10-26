import AppKit
import Observation
import RadioCore

@MainActor @Observable final class AppPreferencesStore {
    static let shared = AppPreferencesStore()
    var values: WorkbenchPreferences { didSet { persist() } }
    var connections: [ConnectionPreset] = []
    var connectionName = ""
    var selectedConnection: UUID?
    var status = ""
    var busy = false
    var storageBytes: Int64 = 0
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private var sessionSave: Task<Void, Never>?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "Workbench.preferences.v1"), let decoded = try? JSONDecoder().decode(WorkbenchPreferences.self, from: data), let valid = try? decoded.validated() { values = valid }
        else { values = WorkbenchPreferences() }
        if let data = defaults.data(forKey: "Workbench.connections.v1"), let stored = try? JSONDecoder().decode([ConnectionPreset].self, from: data), stored.count <= 64, Set(stored.map(\.id)).count == stored.count, stored.allSatisfy({ (try? $0.validated()) != nil }) { connections = stored }
    }
    private func persist() {
        guard let valid = try? values.validated(), let data = try? JSONEncoder().encode(valid) else { return }
        defaults.set(data, forKey: "Workbench.preferences.v1")
        defaults.set([valid.language], forKey: "AppleLanguages")
    }
    var libraryRoot: URL { values.libraryPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultLibraryRoot }
    static var defaultLibraryRoot: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RadioWorkbench", isDirectory: true) }
    func saveConnection(receiver: ReceiverStore) {
        guard !receiver.busy, connections.count < 64 else { return }
        let preset = ConnectionPreset(name: connectionName, audio: receiver.networkPCM, rigctlPort: receiver.rigctl.port)
        do { _ = try preset.validated(); connections.append(preset); selectedConnection = preset.id; try persistConnections(); status = "Perfil de conexión guardado." }
        catch { status = error.localizedDescription }
    }
    func applyConnection(receiver: ReceiverStore) {
        guard !receiver.busy, !receiver.rigctl.busy, let preset = connections.first(where: { $0.id == selectedConnection }) else { return }
        receiver.networkPCM = preset.audio; receiver.rigctl.port = preset.rigctlPort
        status = "Perfil aplicado. La conexión se inicia únicamente al solicitarla."
    }
    func removeConnection() {
        guard let selectedConnection else { return }; connections.removeAll { $0.id == selectedConnection }; self.selectedConnection = nil
        do { try persistConnections() } catch { status = error.localizedDescription }
    }
    private func persistConnections() throws { defaults.set(try JSONEncoder().encode(connections), forKey: "Workbench.connections.v1") }
    func recordDestination(_ destination: WorkbenchDestination) {
        if let data = try? JSONEncoder().encode(destination) { defaults.set(data, forKey: "Workbench.lastSection.v1") }
    }
    var savedDestination: WorkbenchDestination? {
        guard values.rememberSection, let data = defaults.data(forKey: "Workbench.lastSection.v1") else { return nil }
        return try? JSONDecoder().decode(WorkbenchDestination.self, from: data)
    }
    func recordSession(_ receiver: ReceiverStore) {
        guard values.restoreSession, (try? receiver.settings.validated(sampleRate: 384000, mode: receiver.mode)) != nil, receiver.rfBandwidth.isFinite, (100...200000).contains(receiver.rfBandwidth), receiver.networkPCM.isValid else { return }
        let snapshot = ReceiverSessionSnapshot(mode: receiver.mode, settings: receiver.settings, deviceUID: receiver.selectedDeviceID == 0 ? nil : receiver.selectedInput?.uid, source: receiver.inputSource == .tcp ? "tcp" : "device", modulation: receiver.rfModulation, bandwidth: receiver.rfBandwidth, network: receiver.networkPCM)
        sessionSave?.cancel()
        sessionSave = Task { [defaults] in
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); defaults.set(try JSONEncoder().encode(snapshot), forKey: "Workbench.lastSession.v1") } catch { }
        }
    }
    var savedSession: ReceiverSessionSnapshot? {
        guard values.restoreSession, let data = defaults.data(forKey: "Workbench.lastSession.v1"), let session = try? JSONDecoder().decode(ReceiverSessionSnapshot.self, from: data), (try? session.settings.validated(sampleRate: 384000, mode: session.mode)) != nil, session.network.isValid, session.bandwidth.isFinite, (100...200000).contains(session.bandwidth) else { return nil }
        return session
    }
    func refreshStorage() {
        guard !busy else { return }
        let root = libraryRoot
        Task { do { storageBytes = try await LibraryMaintenance().usage(root: root).total } catch { status = error.localizedDescription } }
    }
    func chooseLibrary(receiver: ReceiverStore) {
        guard !busy, !receiver.busy, !receiver.receptionLibrary.busy, !receiver.receptionLibrary.sigMF.busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = AppLocalization.text("Elige el destino. Se copiarán las bibliotecas a una carpeta RadioWorkbenchLibrary nueva; la copia anterior se conserva.")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let destination = parent.appendingPathComponent("RadioWorkbenchLibrary", isDirectory: true), previous = libraryRoot
        busy = true; receiver.receptionLibrary.busy = true; receiver.receptionLibrary.sigMF.busy = true
        Task {
            var reconfigured = false
            defer { busy = false; if !reconfigured { receiver.receptionLibrary.busy = false; receiver.receptionLibrary.sigMF.busy = false } }
            do {
                try await LibraryMaintenance().copyLibraries(from: previous, to: destination)
                receiver.receptionLibrary.busy = false; receiver.receptionLibrary.sigMF.busy = false
                receiver.receptionLibrary.configureStorage(root: destination)
                values.libraryPath = destination.path; reconfigured = true; receiver.receptionLibrary.load(force: true); receiver.receptionLibrary.sigMF.load()
                status = "Carpeta cambiada y copias verificadas. La biblioteca anterior se conserva en su ubicación original."
                storageBytes = try await LibraryMaintenance().usage(root: destination).total
            } catch { status = error.localizedDescription }
        }
    }
    func backupLibrary(receiver: ReceiverStore) {
        guard !busy, !receiver.busy, !receiver.receptionLibrary.busy, !receiver.receptionLibrary.sigMF.busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = "RadioWorkbench-Backup-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let root = libraryRoot, settings = (try? JSONEncoder().encode(PreferencesBackupDocument(preferences: values, connections: connections))) ?? Data()
        busy = true; receiver.receptionLibrary.busy = true; receiver.receptionLibrary.sigMF.busy = true
        Task {
            defer { busy = false; receiver.receptionLibrary.busy = false; receiver.receptionLibrary.sigMF.busy = false }
            do {
                _ = try await LibraryMaintenance().backup(root: root, destination: destination, settings: settings, inputProfiles: AppSupportPaths.inputProfiles)
                status = "Copia de seguridad guardada: audio, I/Q, índices, perfiles y preferencias."
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { status = error.localizedDescription }
        }
    }
    func exportDiagnostic(receiver: ReceiverStore) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "RadioWorkbench-diagnostic.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report: [String: Any] = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development", "language": values.language, "mode": receiver.mode.rawValue, "sampleRate": receiver.captureSampleRate, "receivedSamples": receiver.samplesReceived, "droppedSamples": receiver.dropped, "voiceDroppedSamples": receiver.voiceOutputDropped, "input": receiver.inputSource == .tcp ? "local-tcp" : "audio-device", "engines": engineInventory, "note": "No audio, decoded messages, coordinates, file paths or callsigns included."]
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: url, options: .atomic); status = "Diagnóstico guardado localmente." } catch { status = error.localizedDescription }
    }
    var engineInventory: [String: Bool] {
        var found: [String: Bool] = [:]
        for engine in ["acars", "multimon", "ftx", "cw", "mt63", "ale", "dsc", "itm", "propagation"] {
            found[engine] = FileManager.default.isExecutableFile(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(engine)-helper").path)
        }
        found["DSD-neo"] = ExternalAudioEngine.dsdInstalledURL != nil
        return found
    }
}

struct ReceiverSessionSnapshot: Codable, Sendable {
    let mode: RadioMode
    let settings: DecoderSettings
    let deviceUID: String?
    let source: String
    let modulation: RFModulation
    let bandwidth: Double
    let network: NetworkPCMConfiguration
}

struct PreferencesBackupDocument: Codable {
    let preferences: WorkbenchPreferences
    let connections: [ConnectionPreset]
}
