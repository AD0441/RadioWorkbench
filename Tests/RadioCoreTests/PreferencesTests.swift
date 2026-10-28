import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

@Test func preferencesValidateBoundsAndUseStableIdentifiers() throws {
    var preferences = WorkbenchPreferences()
    #expect(try preferences.validated().language == "es")
    preferences.language = "en"; preferences.lowPower = true
    #expect(try preferences.validated().effectiveFPS == 5)
    preferences.waterfallFPS = 999
    #expect(throws: PreferencesError.self) { try preferences.validated() }
    preferences.waterfallFPS = 25; preferences.defaultChannel = 32
    #expect(throws: PreferencesError.self) { try preferences.validated() }
    var naming = WorkbenchPreferences(); naming.fileNaming = "utc-mode"
    let result = naming.suggestedName(original: "original", mode: .rtty, date: Date(timeIntervalSince1970: 0))
    #expect(result == "1970-01-01T00-00-00Z-rtty")
    #expect(!result.contains(":"))
}

@Test @MainActor func preferencesPersistAndRestoreSessionWithoutStartingInput() async throws {
    let suite = "RWB-preferences-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferencesStore(defaults: defaults)
    preferences.values.language = "en"; preferences.values.waterfallPalette = "amber"
    preferences.recordDestination(.library)
    var settings = DecoderSettings(); settings.frequency = 1500
    let session = ReceiverSessionSnapshot(mode: .rtty, settings: settings, deviceUID: nil, source: "tcp", modulation: .usb, bandwidth: 2400, network: .init())
    defaults.set(try JSONEncoder().encode(session), forKey: "Workbench.lastSession.v1")
    let reloaded = AppPreferencesStore(defaults: defaults)
    #expect(reloaded.values.language == "en")
    #expect(reloaded.values.waterfallPalette == "amber")
    #expect(reloaded.savedDestination == .library)
    #expect(reloaded.savedSession?.mode == .rtty)
    let profilesFolder = FileManager.default.temporaryDirectory.appendingPathComponent("RWB-session-\(UUID())")
    defer { try? FileManager.default.removeItem(at: profilesFolder) }
    let receiver = ReceiverStore(preferences: reloaded, inputProfileURL: profilesFolder.appendingPathComponent("profiles.json"))
    #expect(receiver.mode == .rtty && receiver.settings.frequency == 1500)
    #expect(receiver.inputSource == .tcp)
    #expect(!receiver.busy && !receiver.live && !receiver.rigctl.enabled)
    reloaded.values.restoreSession = false; reloaded.values.rememberSection = false
    #expect(reloaded.savedSession == nil && reloaded.savedDestination == nil)
    #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
}

@Test @MainActor func connectionPresetsRejectRemoteEndpointsAndDoNotAutoConnect() throws {
    let suite = "RWB-connections-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let invalid = ConnectionPreset(name: "remote", audio: .init(host: "192.0.2.1"), rigctlPort: 4532)
    #expect(throws: NetworkPCMError.self) { try invalid.validated() }
    let preset = ConnectionPreset(name: "Brown", audio: .init(port: 7356), rigctlPort: 4533)
    defaults.set(try JSONEncoder().encode([preset]), forKey: "Workbench.connections.v1")
    let preferences = AppPreferencesStore(defaults: defaults)
    #expect(preferences.connections == [preset])
    #expect(preferences.selectedConnection == nil)
}

@Test @MainActor func englishStatusTranslationPreservesValuesAndPlaceholderLikeNames() {
    #expect(AppLocalization.text("General e idioma", language: "en") == "General and language")
    #expect(AppLocalization.text("Guardado: my-{0}-radio.wav. Se conservó una copia del audio original y sus ajustes.", language: "en") == "Saved: my-{0}-radio.wav. Original audio and settings were copied.")
    #expect(AppLocalization.text("Reporte no catalogado de CE3XYZ", language: "en") == "Reporte no catalogado de CE3XYZ")
    #expect(AppLocalization.text("Puerto", language: "es") == "Puerto")
    #expect(AppLocalization.text("Perfil aplicado: SDR++ · {0}. Pulsa Escuchar o abre un WAV.", language: "en") == "Profile applied: SDR++ · {0}. Click Listen or open a WAV.")
    #expect(AppLocalization.text("25.00 % de muestras al límite digital en el bloque.", language: "en") == "25.00 % of samples at the digital limit in this block.")
}

@Test @MainActor func translatedCatalogKeepsPlaceholdersAndNativeFormatTypes() throws {
    let placeholder = try NSRegularExpression(pattern: #"\{\d+\}"#)
    for (source, translation) in AppLocalization.translations {
        func values(_ text: String) -> [String] { placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range,in:text).map { String(text[$0]) } }.sorted() }
        #expect(values(source) == values(translation), Comment(rawValue: source))
    }
    #expect(AppLocalization.translations.count > 1500)
    let path = try #require(AppLocalization.resourceBundle.path(forResource: "en", ofType: "lproj"))
    let english = try #require(Bundle(path: path))
    #expect(english.localizedString(forKey: "Canal %lld", value: nil, table: nil) == "Channel %lld")
    #expect(english.localizedString(forKey: "General e idioma", value: nil, table: nil) == "General and language")
}

@Test(arguments: [5.0,10.0,15.0,25.0]) func visualPreferencesCapFFTWithoutChangingSamples(_ fps: Double) throws {
    let analyzer = LiveSpectrumAnalyzer(sampleRate: 48000, maximumFramesPerSecond: fps)
    var count = 0, last: SpectrumFrame?
    for n in 0..<1000 {
        let samples = (0..<48).map { Float(0.25 * sin(2 * .pi * 1500 * Double(n * 48 + $0) / 48000)) }
        if let frame = analyzer.append(samples, at: Double(n) / 1000) { count += 1; last = frame }
    }
    #expect(abs(Double(count)-fps) <= 1)
    #expect(abs(try #require(last).peakFrequency - 1500) < 24)
}

@Test func libraryRelocationCopiesOnlyLibrariesAndKeepsOriginals() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("RWB-storage-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("old"), target = root.appendingPathComponent("new")
    for path in ["Recepciones/Audio/a.wav","SigMF/recording/data","Engines/private.bin"] {
        let file = source.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1,2,3,4]).write(to: file)
    }
    let maintenance = LibraryMaintenance()
    #expect(try await maintenance.usage(root: source).total == 8)
    try await maintenance.copyLibraries(from: source, to: target)
    #expect(try Data(contentsOf: target.appendingPathComponent("Recepciones/Audio/a.wav")) == Data([1,2,3,4]))
    #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SigMF/recording/data").path))
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("Engines").path))
    await #expect(throws: PreferencesError.self) { try await maintenance.copyLibraries(from: source, to: target) }
    await #expect(throws: PreferencesError.self) { try await maintenance.copyLibraries(from: source, to: source.appendingPathComponent("child")) }
}

@Test func libraryRelocationRejectsSymlinksAndLeavesNoPartialLibrary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("RWB-storage-link-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("old"), target = root.appendingPathComponent("new")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("SigMF"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("SigMF/link"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    await #expect(throws: PreferencesError.self) { try await LibraryMaintenance().copyLibraries(from: source, to: target) }
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("SigMF").path))
}

private actor PreferenceRequestCounter {
    var count = 0
    func add() { count += 1 }
}

@Test @MainActor func manualGuidePolicyDoesNotDownloadUntilRequested() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("RWB-manual-policy-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let counter = PreferenceRequestCounter()
    let eibi = BroadcastService(cacheURL: root.appendingPathComponent("eibi.json"), resourceDirectory: nil, transport: { _ in
        await counter.add(); throw URLError(.notConnectedToInternet)
    })
    let hfcc = HFCCScheduleService(cacheURL: root.appendingPathComponent("hfcc.json"), transport: { _ in
        await counter.add(); throw URLError(.notConnectedToInternet)
    })
    let store = BroadcastStore(service: eibi, hfccService: hfcc, usesSystemNotifications: false)
    store.autoRefreshEnabled = false
    await store.activate(); await store.refreshIfDue()
    #expect(await counter.count == 0)
    #expect(!store.busy)
    await store.refresh()
    #expect(await counter.count > 0)
    #expect(!store.busy)
}

@Test func libraryBackupContainsRecoverableDataAndExcludesEngines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("RWB-backup-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("backup.zip")
    let audio = source.appendingPathComponent("Recepciones/Audio/original.wav")
    try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
    let samples = Data([4,3,2,1]); try samples.write(to: audio)
    let settings = Data("{\"language\":\"en\"}".utf8)
    _ = try await LibraryMaintenance().backup(root: source, destination: target, settings: settings)
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p",target.path,"RadioWorkbench-Backup/Recepciones/Audio/original.wav"]
    process.standardOutput = pipe
    try process.run(); let restored = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    #expect(process.terminationStatus == 0 && restored == samples)
    #expect(try Data(contentsOf: audio) == samples)
}

@Test func waterfallPreferencesChangePaletteAndReduceHistory() throws {
    var amber = WaterfallRaster(height: 40, palette: "amber")
    let amberImage = amber.append([-10])
    let image = try #require(amberImage)
    #expect(image.height == 40)
    let data = try #require(image.dataProvider?.data) as Data
    #expect(Array(data.prefix(4)) == [255,170,30,255])
    var gray = WaterfallRaster(height: 80, palette: "grayscale")
    let grayOptional = gray.append([-10])
    let grayImage = try #require(grayOptional)
    let grayData = try #require(grayImage.dataProvider?.data) as Data
    #expect(Array(grayData.prefix(4)) == [255,255,255,255])
}
