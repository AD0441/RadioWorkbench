import SwiftUI
import UserNotifications

@main
struct RadioWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // App-wide receiver identity; child views observe it through @Bindable.
    private let receiver = ReceiverStore()
    private let updates = UpdateStore()
    private let broadcasts = BroadcastStore()
    private let propagation = PropagationStore()
    private let rbnStore = RBNStore()
    private let consultations = RadioConsultationStore()
    private let aprs = APRSISStore()
    private let satellites = SatelliteConsultationStore()
    var body: some Scene {
        WindowGroup("RadioWorkbench") {
            ContentView(receiver: receiver, broadcasts: broadcasts, propagation: propagation, rbnStore: rbnStore,
                        consultations: consultations, aprs: aprs, satellites: satellites)
                .frame(minWidth: 1100, minHeight: 660)
                .task {
                    updates.activateIfRequested()
                    await MicrophoneDiagnostic.runIfRequested(receiver: receiver)
                    await FileReceptionDiagnostic.runIfRequested(receiver: receiver)
                }
        }
        .defaultSize(width: 1360, height: 850)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Buscar actualizaciones…") { updates.check() }.disabled(updates.configuration == nil || updates.checking || receiver.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button("Abrir audio…") { receiver.openAudio() }.keyboardShortcut("o").disabled(!receiver.mode.isAudioAvailable || !receiver.isDecoderSelected)
                Button("Exportar texto…") { receiver.exportText() }.keyboardShortcut("s").disabled(receiver.text.isEmpty || !receiver.isDecoderSelected)
            }
            CommandMenu("Recepción") {
                Button("Iniciar entrada de audio") { receiver.startLive() }.disabled(receiver.busy || !receiver.mode.isAudioAvailable || !receiver.isDecoderSelected)
                Button("Detener") { receiver.stop() }.keyboardShortcut(".").disabled(!receiver.busy)
                Button("Limpiar texto") { receiver.text = "" }.disabled(receiver.busy || !receiver.isDecoderSelected)
            }
        }
        Settings { PreferencesView(updates: updates, receiver: receiver) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().delegate = self
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
