import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func satelliteFixture(_ name: String) throws -> Data {
    let folder = try #require(Bundle.module.url(forResource: "SatelliteSources", withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: folder.appendingPathComponent(name))
}
private actor SatelliteNetworkSwitch {
    var offline = false
    func setOffline() { offline = true }
}

@Test func satelliteGPReadsRealUTCEpochWithoutZuluAndRejectsNonPhysicalElements() throws {
    let data = try satelliteFixture("gp-utc-no-z.json")
    let orbits = try SatelliteElementParser.omm(data)
    #expect(orbits.count == 6)
    let first = try #require(orbits.first)
    #expect(first.epoch == SatelliteElementParser.utcDate("2026-10-14T06:28:29.257248Z"))
    #expect(SatelliteElementParser.utcDate("2026-10-14T06:28:29.257248") == first.epoch)
    var rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    rows[0]["MEAN_MOTION"] = -2; rows[1]["ECCENTRICITY"] = 1.5
    #expect(try SatelliteElementParser.omm(JSONSerialization.data(withJSONObject: rows)).count == 4)
    #expect(SatelliteElementParser.catalogNumber("A0241") == 100_241)
}

@Test func satelliteTLEChecksChecksumAndMatchesPublishedGPReferenceOrbit() throws {
    let orbits = try SatelliteElementParser.tle(satelliteFixture("amsat-tle.txt"))
    let reference = try #require(SatelliteElementParser.omm(satelliteFixture("gp-utc-no-z.json")).first)
    let tle = try #require(orbits.first { $0.catalogNumber == reference.catalogNumber })
    #expect(abs(tle.meanMotionRevolutionsPerDay - reference.meanMotionRevolutionsPerDay) < 1e-8)
    #expect(abs(tle.epoch.timeIntervalSince(reference.epoch)) < 0.001)
    var lines = String(decoding: try satelliteFixture("amsat-tle.txt"), as: UTF8.self).components(separatedBy: .newlines)
    lines[1] = lines[1].replacingOccurrences(of: "07530", with: "07531")
    let changed = try SatelliteElementParser.tle(Data(lines.joined(separator: "\n").utf8))
    #expect(!changed.contains { $0.catalogNumber == reference.catalogNumber })
}

@Test func satelliteCatalogFallsBackToAMSATAndReadsReportedTimeWithoutBlockingFrequencies() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let tle = try satelliteFixture("amsat-tle.txt"), frequencies = try satelliteFixture("frequencies.json"), reports = try satelliteFixture("reports.json")
    let service = SatelliteCatalogService(cacheURL: directory.appendingPathComponent("catalog.json"), transport: { request in
        let url = request.url!
        let status = url == SatelliteCatalogService.celestrakURL ? 503 : 200
        let data = url == SatelliteCatalogService.amsatOrbitURL ? tle : url == SatelliteCatalogService.statusesURL ? reports : frequencies
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    })
    let now = try #require(SatelliteElementParser.utcDate("2026-10-14T18:00:00Z"))
    let result = try await service.refresh(now: now)
    #expect(result.orbitSource == "AMSAT TLE")
    #expect(result.satellites.contains { $0.noradID == 25544 && !$0.transmitters.isEmpty })
    #expect(result.reports.count == 5)
    #expect(result.orbitsFetchedAt == now && result.frequenciesFetchedAt == now)
    #expect(result.sourceErrors?["Órbitas"]?.contains("503") == true)
    #expect(SatelliteCatalogService.nameAliases("OSCAR 7 (AO-7)").contains("AO7"))
    #expect(SatelliteCatalogService.nameAliases("AO-07_[FM]").contains("AO7"))
}

@Test func satellitePartialUpdatePreservesEachSourceDateAndUsableOfflineOrbits() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gp = try satelliteFixture("gp-utc-no-z.json"), frequencies = try satelliteFixture("frequencies.json"), reports = try satelliteFixture("reports.json")
    let network = SatelliteNetworkSwitch()
    let service = SatelliteCatalogService(cacheURL: directory.appendingPathComponent("catalog.json"), transport: { request in
        if await network.offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!, data = url == SatelliteCatalogService.celestrakURL ? gp : url == SatelliteCatalogService.statusesURL ? reports : frequencies
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    let firstDate = try #require(SatelliteElementParser.utcDate("2026-10-14T18:00:00Z"))
    let first = try await service.refresh(now: firstDate)
    await network.setOffline()
    let second = try await service.refresh(now: firstDate.addingTimeInterval(21_600))
    #expect(second.satellites == first.satellites && second.reports == first.reports)
    #expect(second.orbitsFetchedAt == firstDate && second.frequenciesFetchedAt == firstDate && second.reportsFetchedAt == firstDate)
    #expect(second.sourceErrors?.count == 3)
    #expect(await service.cached()?.satellites == first.satellites)
}

@Test func satelliteFrequencyCertificateFailureStillAllowsOrbitalPassPlanning() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gp = try satelliteFixture("gp-utc-no-z.json"), reports = try satelliteFixture("reports.json")
    let service = SatelliteCatalogService(cacheURL: directory.appendingPathComponent("catalog.json"), transport: { request in
        let url = request.url!
        if url.host == "api.github.com" || url.host == "raw.githubusercontent.com" { throw URLError(.serverCertificateUntrusted) }
        let data = url == SatelliteCatalogService.celestrakURL ? gp : reports
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    let result = try await service.refresh(now: try #require(SatelliteElementParser.utcDate("2026-10-14T18:00:00Z")))
    #expect(result.satellites.count == 6 && result.satellites.allSatisfy { $0.transmitters.isEmpty })
    #expect(result.sourceErrors?["Frecuencias"] != nil && result.orbitsFetchedAt != nil)
}

@Test func satelliteGroundPositionAndSkyTrackShareTheSamePhysicalSolution() throws {
    let orbit = try #require(SatelliteElementParser.omm(satelliteFixture("gp-utc-no-z.json")).first { $0.catalogNumber == 25544 })
    let position = try #require(orbit.position(at: orbit.epoch))
    #expect((-90...90).contains(position.latitude) && (-180...180).contains(position.longitude))
    #expect((300...600).contains(position.altitudeKm))
    let overhead = try #require(orbit.observation(at: orbit.epoch, latitude: position.latitude, longitude: position.longitude))
    #expect(abs(overhead.elevationDegrees - 90) < 0.000001)
    #expect(abs(overhead.rangeKm - position.altitudeKm) < 0.000001)
    let observer = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let pass = try #require(SatellitePassPredictor.passes(orbit: orbit, latitude: observer.latitude, longitude: observer.longitude, from: orbit.epoch, hours: 48).first)
    let track = SatellitePassPredictor.track(orbit: orbit, pass: pass, observer: observer)
    #expect(track.first?.date == pass.aos && track.last?.date == pass.los)
    #expect(track.allSatisfy { (0..<360).contains($0.observation.azimuthDegrees) && (-0.1...90).contains($0.observation.elevationDegrees) })
    let segments = SatellitePassPredictor.segments(track)
    #expect(segments.reduce(0) { $0 + $1.count } == track.count)
}

@MainActor @Test func satelliteSwitchingSelectionClearsPendingPassState() {
    let store = SatelliteConsultationStore()
    store.calculatingPasses = true
    store.selectSatellite(25544)
    #expect(!store.calculatingPasses && store.passes.isEmpty && store.track.isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RADIO_SATELLITE_LIVE"] == "1"))
func satelliteLiveDownloadFromOfficialProviders() async throws {
    let file = URL(fileURLWithPath: "/private/tmp/radioworkbench-satellite-live/catalog.json")
    let result = try await SatelliteCatalogService(cacheURL: file).refresh()
    #expect(result.satellites.count >= 50)
    #expect(result.sourceErrors?["Frecuencias"] == nil)
    #expect(result.satellites.contains { $0.noradID == 25544 && !$0.transmitters.isEmpty })
    print("Satélites reales: \(result.satellites.count), transmisores \(result.frequencies?.count ?? 0), reportes \(result.reports.count), fuente \(result.orbitSource ?? "")")
}
