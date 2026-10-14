import Foundation
import Testing
@testable import RadioCore

@Test func inputProfilesSurviveReloadWithAllReceptionSettings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("InputProfiles.json")
    var settings = DecoderSettings(); settings.frequency = 1865; settings.threshold = 0.001
    settings.audioChannel = .channel(1); settings.sstvFormat = .robot36; settings.sstvRobot36Compatibility = true
    settings.sstvAutoCalibrate = true; settings.imageClockPPM = -18068; settings.sstvNoiseReduction = .strong
    settings.sstvColorRange = .full
    let profile = SavedInputProfile(name: "SDR++ · VHF", deviceUID: "stable-device-uid", deviceName: "VB-Cable", mode: .sstv,
        settings: settings, modulation: .fm, rfBandwidth: 25000)
    var library = InputProfileLibrary(); library.profiles = [profile]; library.lastUsedID = profile.id
    try library.save(to: url)
    let reopened = try InputProfileLibrary.load(from: url)
    #expect(reopened.profiles == [profile]); #expect(reopened.lastUsedID == profile.id)
    #expect(reopened.profiles[0].deviceUID == "stable-device-uid")
    var updated = reopened; updated.profiles[0].settings.audioChannel = .mix
    try updated.save(to: url)
    #expect(try InputProfileLibrary.load(from: url).profiles[0].settings.audioChannel == .mix)
}

@Test func invalidProfileSavePreservesPreviousFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    var library = InputProfileLibrary()
    library.profiles = [SavedInputProfile(name: "Micrófono", deviceUID: "builtin-uid", deviceName: "Mic", mode: .morse,
        settings: DecoderSettings(), modulation: .usb, rfBandwidth: 2400)]
    try library.save(to: url); let original = try Data(contentsOf: url)
    library.profiles[0].settings.imageClockPPM = 90000
    #expect(throws: Error.self) { try library.save(to: url) }
    #expect(try Data(contentsOf: url) == original)
    library.profiles[0].settings.imageClockPPM = 0; library.schemaVersion = 99
    #expect(throws: Error.self) { try library.save(to: url) }
    #expect(try Data(contentsOf: url) == original)
}

@Test func corruptAndAmbiguousProfileLibrariesAreRejected() throws {
    var library = InputProfileLibrary()
    let profile = SavedInputProfile(name: "Mic", deviceUID: nil, deviceName: "Predeterminada", mode: .morse,
        settings: DecoderSettings(), modulation: .usb, rfBandwidth: 2400)
    library.profiles = [profile, profile]
    #expect(throws: Error.self) { try library.validate() }
    library.profiles = [profile]; library.lastUsedID = UUID()
    #expect(throws: Error.self) { try library.validate() }
    library.lastUsedID = nil; library.profiles[0].settings.audioChannel = .channel(-1)
    #expect(throws: Error.self) { try library.validate() }
}
