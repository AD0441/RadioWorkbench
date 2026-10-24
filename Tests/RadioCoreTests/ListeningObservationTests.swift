import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func listeningNote(at date: Date = Date(timeIntervalSince1970: 1_792_800_000)) -> ListeningObservation {
    var item = ListeningObservation(observedAt: date, stationName: "Emisora de prueba", frequencyHz: 9_410_000,
        modulation: "AM", receivingStation: .init(location: RadioLocation(latitude: -33.45, longitude: -70.67), receiver: "SDR", antenna: "Dipolo"))
    item.transmitter = RadioLocation(latitude: 40, longitude: -4)
    item.transmitterName = "Sitio confirmado"; item.transmitterSource = "Datos de prueba"
    return item
}

@Test func listeningLibraryMigratesV1WithoutLosingAudioAndPersistsNotes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-listening-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ReceptionLibraryRepository(directory: directory)
    let source = try #require(Bundle.module.url(forResource: "morse_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let audio = try await repository.importAudio(from: source, title: "Audio previo", mode: .morse, settings: .init(), rf: .init(modulation: .usb, bandwidthHz: 2400))
    let index = directory.appendingPathComponent("library.json")
    var old = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
    old["schemaVersion"] = 1; old.removeValue(forKey: "observations")
    try JSONSerialization.data(withJSONObject: old).write(to: index)
    let originalIndex = try Data(contentsOf: index)
    let migrated = ReceptionLibraryRepository(directory: directory)
    #expect(try await migrated.load() == [audio])
    #expect(try await migrated.loadObservations().isEmpty)
    var note = listeningNote(); note.audioSessionID = audio.id
    try await migrated.saveObservation(note)
    #expect(try Data(contentsOf: directory.appendingPathComponent("library-schema-1-backup.json")) == originalIndex)
    let reopened = ReceptionLibraryRepository(directory: directory)
    #expect(try await reopened.load() == [audio])
    #expect(try await reopened.loadObservations() == [note])
    #expect(try Data(contentsOf: await reopened.audioURL(for: audio.id)) == Data(contentsOf: source))
    try await reopened.trashObservation(id: note.id)
    #expect(try await reopened.loadObservations().first?.isTrashed == true)
    try await reopened.trashObservation(id: note.id, restore: true)
    #expect(try await reopened.loadObservations() == [note])
}

@Test func listeningAnnotationNeedsNeitherDecoderNorAudioAndCanResolveSiteLater() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-note-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ReceptionLibraryRepository(directory: directory)
    var item = listeningNote(); item.transmitter = nil; item.outcome = .notHeard
    try await repository.saveObservation(item)
    #expect(try await repository.load().isEmpty)
    #expect(try await repository.loadObservations().first?.distanceKm == nil)
    item.transmitter = RadioLocation(latitude: 40, longitude: -4)
    try await repository.saveObservation(item)
    #expect(try await repository.loadObservations().count == 1)
    #expect(try await repository.loadObservations().first?.distanceKm ?? 0 > 10_000)
}

@Test func listeningInvalidUpdatePreservesIndexAndSnapshotIsIndependent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rwb-note-invalid-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = ReceptionLibraryRepository(directory: directory)
    let item = listeningNote(); try await repository.saveObservation(item)
    let index = directory.appendingPathComponent("library.json"), bytes = try Data(contentsOf: index)
    var changedProfile = item.receivingStation; changedProfile.antenna = "Otra antena"
    #expect(item.receivingStation.antenna == "Dipolo")
    var invalid = item; invalid.endedAt = item.observedAt.addingTimeInterval(-1)
    await #expect(throws: ReceptionLibraryError.self) { try await repository.saveObservation(invalid) }
    invalid = item; invalid.audioSessionID = UUID()
    await #expect(throws: ReceptionLibraryError.self) { try await repository.saveObservation(invalid) }
    #expect(try Data(contentsOf: index) == bytes)
    #expect(try await repository.loadObservations() == [item])
}

@Test func listeningFiltersCrossMidnightUseChosenTimezoneAndSeparateRemoteAntennas() throws {
    let formatter = ISO8601DateFormatter(), date = try #require(formatter.date(from: "2026-10-24T01:00:00Z"))
    var item = listeningNote(at: date)
    var filter = ListeningFilter(); filter.firstHour = 22; filter.lastHour = 2
    filter.antenna = "Dipolo"; filter.band = "31 m"; filter.origin = .local
    #expect(filter.includes(item))
    filter.from = date.addingTimeInterval(1); #expect(!filter.includes(item)); filter.from = nil
    item.receivingStation.origin = .remote; #expect(!filter.includes(item)); item.receivingStation.origin = .local
    filter.timeZone = try #require(TimeZone(secondsFromGMT: -4 * 3600))
    #expect(!filter.includes(item)) // 21:00 local is outside 22:00–02:59.
    filter.firstHour = 21; #expect(filter.includes(item))
    filter.evidence = .audio; #expect(!filter.includes(item))
    item.audioSessionID = UUID(); #expect(filter.includes(item))
    filter.firstHour = -1; #expect(!filter.includes(item)); filter.firstHour = 21
    item.trashedAt = Date(); #expect(!filter.includes(item))
}

@Test @MainActor func hfRXAndBilateralLinkKeepSeparateAssumptionsAndCorrectEndpoints() throws {
    let store = PropagationStore(), local = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    store.targetLatitude = "40"; store.targetLongitude = "-4"; store.r12 = "70"
    #expect(store.listening && store.watts.isEmpty && !store.estimatesReception)
    #expect(store.pathSummary(origin: local, date: Date()).contains("km"))
    store.frequencyMHz = "0.8" // MF geometry remains useful, outside P.533.
    #expect(store.input(origin: local, date: Date()) == nil)
    #expect(store.pathSummary(origin: local, date: Date()).contains("rumbo"))
    store.frequencyMHz = "9.41"; store.watts = "250000"; store.bandwidth = "9000"
    let listening = try #require(store.input(origin: local, date: Date()))
    #expect(listening.origin.latitude == 40 && listening.target == local)
    store.listening = false
    #expect(store.watts == "100" && store.bandwidth == "2400")
    store.watts = "50"; store.rxGain = "3"; store.noise = 0
    store.returnWatts = "10"; store.returnTXGain = "6"; store.returnRXGain = "2"; store.returnBandwidth = "500"; store.returnNoise = 3
    let forward = try #require(store.input(origin: local, date: Date()))
    let reverse = try #require(store.reverseInput(origin: local, date: forward.date))
    #expect(forward.origin == local && forward.target == reverse.origin && reverse.target == local)
    #expect(forward.watts == 50 && reverse.watts == 10 && reverse.bandwidth == 500)
    #expect(forward.rxGain == 3 && reverse.txGain == 6 && reverse.rxGain == 2 && reverse.noise == 3)
    let exported = store.hfPlanningDataText(origin: local, date: forward.date)
    #expect(exported.contains("potencia TX B: 10 W") && exported.contains("ancho RX A: 500 Hz"))
    store.listening = true
    #expect(store.watts == "250000" && store.bandwidth == "9000")
}

@Test func listeningMapSplitsPacificGreatCircleAndKeepsEndpoints() throws {
    let a = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let b = try #require(RadioLocation(latitude: 35.68, longitude: 139.69))
    let segments = a.greatCircleSegments(to: b)
    #expect(segments.count == 2 && segments.first?.first == a && segments.last?.last == b)
    #expect(segments.allSatisfy { segment in zip(segment, segment.dropFirst()).allSatisfy { abs($0.longitude - $1.longitude) <= 180 } })
    let sum = segments.reduce(0.0) { total, segment in total + zip(segment, segment.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) } }
    #expect(abs(sum - a.distance(to: b)) < 1)
    #expect(a.greatCircleSegments(to: a).first?.first == a)
}
