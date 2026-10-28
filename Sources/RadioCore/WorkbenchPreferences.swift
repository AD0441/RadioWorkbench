import Foundation

public struct WorkbenchPreferences: Codable, Equatable, Sendable {
    public var language = "es"
    public var rememberSection = true
    public var restoreSession = true
    public var defaultInputSource = "device"
    public var defaultDeviceUID = ""
    public var defaultChannel = -1
    public var warnClipping = true
    public var warnDroppedSamples = true
    public var appearance = "system"
    public var textSize = 13
    public var waterfallPalette = "ocean"
    public var waterfallFPS = 25
    public var lowPower = false
    public var libraryPath: String?
    public var fileNaming = "original"
    public var guideAutomatic = true
    public var guideHours = 6
    public var satelliteAutomatic = true
    public var satelliteHours = 6
    public var conditionsAutomatic = true
    public var conditionsMinutes = 3
    public var notifications = true
    public init() {}
    public var effectiveFPS: Double { lowPower ? 5 : Double(waterfallFPS) }
    public func validated() throws -> Self {
        guard ["es", "en"].contains(language), ["device", "tcp"].contains(defaultInputSource),
              (-1...31).contains(defaultChannel), ["system", "light", "dark"].contains(appearance),
              (11...20).contains(textSize), ["ocean", "amber", "grayscale"].contains(waterfallPalette),
              [5,10,15,25].contains(waterfallFPS), ["original","utc-mode","mode-utc"].contains(fileNaming),
              [1,6,12,24].contains(guideHours), [6,12,24,48].contains(satelliteHours),
              [3,5,15,30].contains(conditionsMinutes), defaultDeviceUID.count <= 1024,
              libraryPath.map({ $0.hasPrefix("/") && $0.utf8.count <= 4096 }) ?? true else { throw PreferencesError.invalid }
        return self
    }
    public func suggestedName(original: String, mode: RadioMode, date: Date = Date()) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        let stamp = f.string(from: date).replacingOccurrences(of: ":", with: "-")
        switch fileNaming {
        case "utc-mode": return stamp + "-" + mode.rawValue
        case "mode-utc": return mode.rawValue + "-" + stamp
        default: return String(original.prefix(120))
        }
    }
}

public enum PreferencesError: LocalizedError {
    case invalid, destinationNotEmpty, unsafeFolder
    public var errorDescription: String? {
        switch self {
        case .invalid: "Los ajustes no son válidos. Se conserva la configuración anterior."
        case .destinationNotEmpty: "La carpeta de destino ya contiene una biblioteca. Elige una carpeta vacía."
        case .unsafeFolder: "Elige una carpeta local distinta de la biblioteca actual y de sus subcarpetas."
        }
    }
}

public struct ConnectionPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var audio: NetworkPCMConfiguration
    public var rigctlPort: UInt16
    public init(id: UUID = UUID(), name: String, audio: NetworkPCMConfiguration, rigctlPort: UInt16) {
        self.id = id; self.name = name; self.audio = audio; self.rigctlPort = rigctlPort
    }
    public func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, rigctlPort > 0 else { throw PreferencesError.invalid }
        _ = try audio.validated(); return self
    }
}
