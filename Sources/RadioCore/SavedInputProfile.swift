import Foundation

public struct SavedInputProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    // HAL numeric IDs can change after reboot; only the persistent UID is saved.
    public var deviceUID: String?
    public var deviceName: String
    public var mode: RadioMode
    public var settings: DecoderSettings
    public var modulation: RFModulation
    public var rfBandwidth: Double
    public init(id: UUID = UUID(), name: String, deviceUID: String?, deviceName: String,
                mode: RadioMode, settings: DecoderSettings, modulation: RFModulation, rfBandwidth: Double) {
        self.id = id; self.name = name; self.deviceUID = deviceUID; self.deviceName = deviceName
        self.mode = mode; self.settings = settings; self.modulation = modulation; self.rfBandwidth = rfBandwidth
    }
}

public struct InputProfileLibrary: Codable, Sendable {
    public var schemaVersion = 1
    public var profiles: [SavedInputProfile] = []
    public var lastUsedID: UUID?
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1, profiles.count <= 64, Set(profiles.map(\.id)).count == profiles.count,
              lastUsedID == nil || profiles.contains(where: { $0.id == lastUsedID }) else { throw InputProfileError.invalidLibrary }
        for profile in profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.name.count <= 80,
                  profile.deviceUID.map({ !$0.isEmpty }) ?? true,
                  profile.rfBandwidth.isFinite, (100...200000).contains(profile.rfBandwidth) else { throw InputProfileError.invalidLibrary }
            try profile.settings.validated(sampleRate: 384000, mode: profile.mode)
            if case .channel(let index) = profile.settings.audioChannel, !(0..<32).contains(index) { throw InputProfileError.invalidLibrary }
        }
    }
    public static func load(from url: URL) throws -> Self {
        let library = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try library.validate(); return library
    }
    public func save(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public enum InputProfileError: LocalizedError {
    case invalidLibrary
    public var errorDescription: String? { "El archivo de perfiles tiene una versión o ajustes no válidos. Se conserva para poder recuperarlo." }
}
