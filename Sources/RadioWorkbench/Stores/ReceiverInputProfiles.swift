import Foundation
import RadioCore

extension ReceiverStore {
    private var profilesURL: URL {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--profiles-path"), index + 1 < args.count { return URL(fileURLWithPath: args[index + 1]) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench/InputProfiles.json")
    }
    func loadInputProfiles() {
        do {
            if FileManager.default.fileExists(atPath: profilesURL.path) {
                inputProfiles = try InputProfileLibrary.load(from: profilesURL)
            } else {
                for device in devices.filter({ $0.isBuiltIn || $0.uid.lowercased().contains("vbcable") }) {
                    var options = DecoderSettings(); options.frequency = 1900
                    options.threshold = device.isBuiltIn ? 0.001 : 0.01
                    if device.isBuiltIn { options.sstvFormat = .robot36; options.sstvRobot36Compatibility = true }
                    inputProfiles.profiles.append(SavedInputProfile(name: device.isBuiltIn ? "Micrófono · Robot36C" : "SDR++ · VB-Cable",
                        deviceUID: device.uid, deviceName: device.name, mode: .sstv, settings: options, modulation: .usb, rfBandwidth: 3000))
                }
                // Seed both useful routes without silently changing the
                // established default input or decoder on first launch.
                inputProfiles.lastUsedID = nil
                try inputProfiles.save(to: profilesURL)
            }
            if let id = inputProfiles.lastUsedID { applyInputProfile(id, persist: false) }
        } catch { profileNotice = "No se pudieron cargar los perfiles: \(error.localizedDescription)" }
    }
    func applyInputProfile(_ id: UUID, persist: Bool = true) {
        guard !busy, let profile = inputProfiles.profiles.first(where: { $0.id == id }) else { return }
        refreshDevices()
        let deviceID: UInt32
        if let uid = profile.deviceUID {
            guard let device = devices.first(where: { $0.uid == uid }) else {
                selectedProfileID = nil
                profileNotice = "La entrada «\(profile.deviceName)» del perfil no está conectada. Conéctala y pulsa Actualizar."
                return
            }
            deviceID = device.id
            if case .channel(let index) = profile.settings.audioChannel, index >= device.channels {
                selectedProfileID = nil; profileNotice = "El canal guardado no está disponible en esta entrada."; return
            }
        } else { deviceID = 0 }
        select(profile.mode); selectedDeviceID = deviceID; sourceChannelCount = 0
        settings = profile.settings; rfModulation = profile.modulation; rfBandwidth = profile.rfBandwidth
        selectedProfileID = id; inputProfiles.lastUsedID = id
        profileNotice = "Perfil aplicado: \(profile.name). Pulsa Escuchar o abre un WAV."
        if persist { persistInputProfiles() }
    }
    func saveInputProfile(updating: Bool) {
        guard !busy else { return }
        let old = updating ? inputProfiles.profiles.first(where: { $0.id == selectedProfileID }) : nil
        let name = (old?.name ?? newProfileName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { profileNotice = "Escribe un nombre de 1 a 80 caracteres."; return }
        let device = selectedInput
        let profile = SavedInputProfile(id: old?.id ?? UUID(), name: name,
            deviceUID: selectedDeviceID == 0 ? nil : device?.uid,
            deviceName: selectedDeviceID == 0 ? "Predeterminada del sistema" : device?.name ?? "Entrada de audio",
            mode: mode, settings: settings, modulation: rfModulation, rfBandwidth: rfBandwidth)
        var library = inputProfiles
        if let index = library.profiles.firstIndex(where: { $0.id == profile.id }) { library.profiles[index] = profile }
        else { library.profiles.append(profile) }
        library.lastUsedID = profile.id
        do {
            try library.save(to: profilesURL); inputProfiles = library; selectedProfileID = profile.id
            showsProfileEditor = false; profileNotice = "Perfil guardado: \(name). Se recuperará al abrir la app."
        } catch { profileNotice = "No se pudo guardar: \(error.localizedDescription)" }
    }
    func removeInputProfile() {
        guard !busy, let id = selectedProfileID else { return }
        var library = inputProfiles; library.profiles.removeAll { $0.id == id }; library.lastUsedID = nil
        do {
            try library.save(to: profilesURL); inputProfiles = library; selectedProfileID = nil
            profileNotice = "Perfil eliminado. Los ajustes actuales siguen disponibles para guardar otro perfil."
        } catch { profileNotice = "No se pudo eliminar: \(error.localizedDescription)" }
    }
    private func persistInputProfiles() {
        do { try inputProfiles.save(to: profilesURL) }
        catch { profileNotice = "No se pudo conservar la selección: \(error.localizedDescription)" }
    }
}
