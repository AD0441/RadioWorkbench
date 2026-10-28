import AppKit
import Observation
import Sparkle
import RadioCore

@MainActor @Observable final class UpdateStore: NSObject, SPUUpdaterDelegate {
    var status = "Busca nuevas versiones cuando lo solicites. Las descargas e instalación requieren tu acción."
    var checking = false
    var automaticallyChecks: Bool
    let configuration: UpdateFeedConfiguration?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var started = false
    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyChecks = defaults.bool(forKey: "RadioWorkbench.AutomaticUpdateChecks")
        configuration = UpdateFeedConfiguration(feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        super.init()
        if configuration != nil, bundle.bundleURL.pathExtension == "app" {
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        } else { status = "Las actualizaciones firmadas están disponibles en la app empaquetada con su canal configurado." }
    }
    func activateIfRequested() {
        if automaticallyChecks { start() }
    }
    func setAutomatic(_ enabled: Bool) {
        automaticallyChecks = enabled; defaults.set(enabled, forKey: "RadioWorkbench.AutomaticUpdateChecks")
        if enabled { start() }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
    private func start() {
        guard !started, let controller else { return }
        do {
            try controller.updater.start()
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            controller.updater.automaticallyDownloadsUpdates = false
            started = true
        } catch { status = error.localizedDescription }
    }
    func check() {
        start()
        guard started, let controller, controller.updater.canCheckForUpdates else { return }
        checking = true; status = "Comprobando el canal de actualizaciones firmado…"
        controller.checkForUpdates(nil)
    }
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let message = error?.localizedDescription ?? "Comprobación terminada; revisa el resultado de Sparkle."
        Task { @MainActor [weak self] in self?.checking = false; self?.status = message }
    }
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.checking = false; self?.status = message }
    }
}
