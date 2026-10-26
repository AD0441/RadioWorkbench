import SwiftUI
import UserNotifications

@main
struct RadioWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // App-wide receiver identity; child views observe it through @Bindable.
    private let preferences = AppPreferencesStore.shared
    private let receiver = ReceiverStore(preferences: .shared)
    private let updates = UpdateStore()
    private let broadcasts = BroadcastStore()
    private let propagation = PropagationStore()
    private let rbnStore = RBNStore()
    private let consultations = RadioConsultationStore()
    private let aprs = APRSISStore()
    private let satellites = SatelliteConsultationStore()
    init() { applyPreferences() }
    var body: some Scene {
        WindowGroup("RadioWorkbench") {
            ContentView(receiver: receiver, broadcasts: broadcasts, propagation: propagation, rbnStore: rbnStore,
                        consultations: consultations, aprs: aprs, satellites: satellites)
                .environment(preferences)
                .environment(\.locale, Locale(identifier: preferences.values.language))
                .preferredColorScheme(preferences.values.appearance == "system" ? nil : preferences.values.appearance == "dark" ? .dark : .light)
                .font(.system(size: CGFloat(preferences.values.textSize)))
                .environment(\.dynamicTypeSize, preferences.values.textSize >= 16 ? .xxxLarge : .large)
                .frame(minWidth: 1100, minHeight: 660)
                .onChange(of: preferences.values) { applyPreferences() }
                .onChange(of: preferences.values.notifications) { Task { await broadcasts.rescheduleAlerts() } }
                .onChange(of: receiver.settings) { preferences.recordSession(receiver) }
                .onChange(of: receiver.selectedDeviceID) { preferences.recordSession(receiver) }
                .onChange(of: receiver.inputSource) { preferences.recordSession(receiver) }
                .onChange(of: receiver.networkPCM) { preferences.recordSession(receiver) }
                .onChange(of: receiver.rfModulation) { preferences.recordSession(receiver) }
                .onChange(of: receiver.rfBandwidth) { preferences.recordSession(receiver) }
                .onChange(of: receiver.destination) { preferences.recordDestination(receiver.destination); preferences.recordSession(receiver) }
                .task {
                    applyPreferences()
                    updates.activateIfRequested()
                    await MicrophoneDiagnostic.runIfRequested(receiver: receiver)
                    await FileReceptionDiagnostic.runIfRequested(receiver: receiver)
                }
        }
        .defaultSize(width: 1360, height: 850)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(AppLocalization.text("Buscar actualizaciones…")) { updates.check() }.disabled(updates.configuration == nil || updates.checking || receiver.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button(AppLocalization.text("Abrir audio…")) { receiver.openAudio() }.keyboardShortcut("o").disabled(!receiver.mode.isAudioAvailable || !receiver.isDecoderSelected)
                Button(AppLocalization.text("Exportar texto…")) { receiver.exportText() }.keyboardShortcut("s").disabled(receiver.text.isEmpty || !receiver.isDecoderSelected)
            }
            CommandMenu(AppLocalization.text("Recepción")) {
                Button(AppLocalization.text("Iniciar entrada de audio")) { receiver.startLive() }.disabled(receiver.busy || !receiver.mode.isAudioAvailable || !receiver.isDecoderSelected)
                Button(AppLocalization.text("Detener")) { receiver.stop() }.keyboardShortcut(".").disabled(!receiver.busy)
                Button(AppLocalization.text("Limpiar texto")) { receiver.text = "" }.disabled(receiver.busy || !receiver.isDecoderSelected)
            }
        }
        Settings {
            PreferencesView(preferences: preferences, updates: updates, receiver: receiver, broadcasts: broadcasts, propagation: propagation, satellites: satellites)
                .environment(\.locale, Locale(identifier: preferences.values.language))
                .preferredColorScheme(preferences.values.appearance == "system" ? nil : preferences.values.appearance == "dark" ? .dark : .light)
                .font(.system(size: CGFloat(preferences.values.textSize)))
        }
    }
    private func applyPreferences() {
        let values = preferences.values
        receiver.applyDisplayPreferences(values)
        broadcasts.autoRefreshEnabled = values.guideAutomatic; broadcasts.autoRefreshHours = values.guideHours
        broadcasts.notificationsEnabled = values.notifications
        propagation.autoRefreshEnabled = values.conditionsAutomatic; propagation.autoRefreshMinutes = values.conditionsMinutes
        satellites.autoRefreshEnabled = values.satelliteAutomatic; satellites.autoRefreshHours = values.satelliteHours
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
