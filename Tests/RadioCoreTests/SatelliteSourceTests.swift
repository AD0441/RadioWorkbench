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

@Test func satelliteOneHourWindowKeepsFullPassWhenAlreadyInProgressOrEndingLater() throws {
    let orbit = try #require(SatelliteElementParser.omm(satelliteFixture("gp-utc-no-z.json")).first { $0.catalogNumber == 25544 })
    let full = try #require(SatellitePassPredictor.passes(orbit: orbit, latitude: -33.45, longitude: -70.67,
        from: orbit.epoch, hours: 48, stepSeconds: 20).first)
    // Both boundaries lie inside an actual SGP4 pass. The old implementation lost
    // this pass or replaced its true AOS with the beginning of the requested window.
    let short = DateInterval(start: full.maximumAt.addingTimeInterval(-15), duration: 30)
    let result = try #require(SatellitePassPredictor.passes(orbit: orbit, latitude: -33.45, longitude: -70.67,
        window: short, stepSeconds: 20).first)
    #expect(result.aos < short.start && result.los > short.end)
    #expect(abs(result.aos.timeIntervalSince(full.aos)) < 2)
    #expect(abs(result.los.timeIntervalSince(full.los)) < 2)
    #expect(!result.aosClipped && !result.losClipped)
    #expect(result.usefulDuration(in: short) == 30)
    let hourEndingDuringPass = DateInterval(start: full.aos.addingTimeInterval(-3540), duration: 3600)
    let crossingEnd = try #require(SatellitePassPredictor.passes(orbit: orbit, latitude: -33.45, longitude: -70.67,
        window: hourEndingDuringPass, stepSeconds: 20).first)
    #expect(crossingEnd.aos < hourEndingDuringPass.end && crossingEnd.los > hourEndingDuringPass.end)
    #expect(abs(crossingEnd.los.timeIntervalSince(full.los)) < 2)
}

@Test func satellitePassWindowRejectsNonFiniteStepsAndDoesNotIncludeTouchingIntervals() {
    let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    let orbit = TLEOrbit(name: "Test", catalogNumber: 99999, epoch: epoch, meanMotionRevolutionsPerDay: 15.5,
        eccentricity: 0.001, inclinationDegrees: 51.6, raanDegrees: 12, argumentOfPerigeeDegrees: 50, meanAnomalyDegrees: 180)
    let window = DateInterval(start: epoch, duration: 3600)
    #expect(SatellitePassPredictor.passes(orbit: orbit, latitude: 0, longitude: 0, window: window, stepSeconds: .infinity).isEmpty)
    #expect(SatellitePassPredictor.passes(orbit: orbit, latitude: .nan, longitude: 0, window: window).isEmpty)
    let ended = SatellitePass(satellite: "Test", aos: epoch.addingTimeInterval(-600), maximumElevation: 30,
        maximumAt: epoch.addingTimeInterval(-300), los: epoch)
    #expect(!ended.overlaps(window) && ended.usefulDuration(in: window) == 0)
}

@Test func satelliteDownlinkSelectionUsesPublishedTransmitterIncludingInvertedPassbandsAndBeacons() throws {
    let transmitters = try JSONDecoder().decode([AmateurSatelliteTransmitter].self, from: satelliteFixture("frequencies.json"))
    let ao7 = try #require(transmitters.first { $0.downlink == "145.975-145.925" })
    let options = SatelliteDownlink.options(for: ao7)
    let downlink = try #require(options.first { !$0.isBeacon })
    #expect(downlink.lowerMHz == 145.925 && downlink.upperMHz == 145.975)
    #expect(abs(downlink.nominalMHz - 145.950) < 1e-10 && downlink.isPassband)
    #expect(options.contains { $0.isBeacon && $0.nominalMHz == 145.970 })
    let iss = try #require(transmitters.first { $0.downlink == "437.825" })
    #expect(SatelliteDownlink.options(for: iss).first?.nominalMHz == 437.825)
    let invalid = try JSONDecoder().decode(AmateurSatelliteTransmitter.self,
        from: Data(#"{"name":"Bad","downlink":"unknown / NaN / 145.8 kHz / -145.8"}"#.utf8))
    #expect(SatelliteDownlink.options(for: invalid).isEmpty)
}

@Test func satelliteCachedReportsExpireAtPresentationAndDoNotImplyTransmitterActivity() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let orbit = try #require(SatelliteElementParser.omm(satelliteFixture("gp-utc-no-z.json")).first { $0.catalogNumber == 25544 })
    let satellite = AmateurSatellite(name: "ISS", noradID: 25544, orbit: orbit, transmitters: [])
    let recent = SatelliteStatusReport(satelliteName: "ISS", report: "Heard", reportedAt: now.addingTimeInterval(-71 * 3600))
    let old = SatelliteStatusReport(satelliteName: "ISS", report: "Heard", reportedAt: now.addingTimeInterval(-73 * 3600))
    let future = SatelliteStatusReport(satelliteName: "ISS", report: "Heard", reportedAt: now.addingTimeInterval(3600))
    #expect(SatelliteConsultationStore.latestStatus(for: satellite, reports: [old, recent, future], now: now) == recent)
    #expect(SatelliteConsultationStore.latestStatus(for: satellite, reports: [old, recent], now: now.addingTimeInterval(2 * 3600)) == nil)
}

@MainActor @Test func satelliteOpportunityRetainsReceiverAndExactDownlinkWhenOpened() throws {
    let orbits = try SatelliteElementParser.omm(satelliteFixture("gp-utc-no-z.json"))
    let orbit = try #require(orbits.first { $0.catalogNumber == 25544 })
    let transmitters = try JSONDecoder().decode([AmateurSatelliteTransmitter].self, from: satelliteFixture("frequencies.json"))
        .filter { $0.downlink == "437.825" }
    let satellite = AmateurSatellite(name: "ISS", noradID: 25544, orbit: orbit, transmitters: transmitters)
    let observer = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let pass = try #require(SatellitePassPredictor.passes(orbit: orbit, latitude: observer.latitude, longitude: observer.longitude,
        from: orbit.epoch, hours: 48).first)
    let window = DateInterval(start: pass.maximumAt.addingTimeInterval(-30), duration: 3600)
    let results = SatelliteConsultationStore.opportunities(satellites: [satellite], reports: [], observer: observer, window: window, minimumPeak: 5)
    let opportunity = try #require(results.first)
    let store = SatelliteConsultationStore()
    store.snapshot = SatelliteCatalogSnapshot(satellites: [satellite], reports: [], fetchedAt: orbit.epoch,
        orbits: nil, frequencies: nil, orbitSource: nil, orbitsFetchedAt: nil, frequenciesFetchedAt: nil, reportsFetchedAt: nil, sourceErrors: nil)
    store.searchWindow = window; store.searchObserver = observer; store.nextHour = results
    store.showOpportunity(opportunity)
    #expect(store.selectedID == 25544 && store.observer == observer)
    #expect(store.selectedDownlink?.nominalMHz == 437.825)
    #expect(store.selectedPass?.aos == opportunity.pass.aos && !store.track.isEmpty)
    #expect((0...100).contains(opportunity.factors.score))
    #expect(opportunity.factors.usefulSeconds <= 3600)
    #expect(opportunity.factors.explanation.contains("No es una probabilidad"))
    #expect(store.nextHour.count == results.count)
    store.clearPasses()
    #expect(store.nextHour.isEmpty && store.searchWindow == nil && store.observer == nil)
}

@Test func satelliteElevationSearchMatchesFullObservationWithoutRangeRateWork() throws {
    let orbit = try #require(SatelliteElementParser.omm(satelliteFixture("gp-utc-no-z.json")).first)
    for seconds in stride(from: 0.0, through: 600, by: 60) {
        let date = orbit.epoch.addingTimeInterval(seconds)
        let elevation = try #require(orbit.elevationDegrees(at: date, latitude: -33.45, longitude: -70.67))
        let full = try #require(orbit.observation(at: date, latitude: -33.45, longitude: -70.67))
        #expect(abs(elevation - full.elevationDegrees) < 1e-10)
    }
}
