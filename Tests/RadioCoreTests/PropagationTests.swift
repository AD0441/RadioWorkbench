import Foundation
import Testing
@testable import RadioCore

private func propagationDate(_ text: String) -> Date { SpaceWeatherParser.date(text)! }
private func weatherFixture(_ name: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("SpaceWeather/\(name)"))
}

@Test func propagationParsesOfficialSpaceWeatherFixtures() throws {
    let now = propagationDate("2026-10-13T14:10:00Z")
    let kp = try SpaceWeatherParser.reading(weatherFixture("kp.json"), field: "estimated_kp", fetchedAt: now)
    #expect(kp.isFresh(at: now, maxAge: 900))
    let flux = try SpaceWeatherParser.reading(weatherFixture("flux.json"), field: "flux", fetchedAt: now)
    #expect(flux.value == 123)
    #expect(flux.observedAt == propagationDate("2026-10-12T22:00:00Z"))
    let scales = try SpaceWeatherParser.scales(weatherFixture("scales.json"), fetchedAt: now)
    #expect(scales.radio == 0 && scales.radiation == 0 && scales.geomagnetic == 0)
    let grid = try SpaceWeatherParser.absorption(String(decoding: weatherFixture("drap.txt"), as: UTF8.self), fetchedAt: now)
    #expect(grid.validAt == propagationDate("2026-10-13T14:04:00Z"))
    #expect(grid.longitudes.count == 90 && grid.latitudes.count == 90)
    let cell = try #require(grid.nearest(to: RadioLocation(latitude: -33.45, longitude: -70.67)!))
    #expect(cell.latitude == -33 && cell.longitude == -70)
    #expect(!grid.isFresh(at: now.addingTimeInterval(3600)))
    let indices = try SpaceWeatherParser.indices(String(decoding: weatherFixture("itu-indices.html"), as: UTF8.self))
    #expect(indices.first(where: { $0.id == "2026-10" })?.r12 == 75)
    #expect(indices.first(where: { $0.id == "2026-10" })?.predicted == true)
    #expect(indices.first(where: { $0.id == "2024-01" })?.r12 == 131)
    #expect(indices.first(where: { $0.id == "2024-01" })?.predicted == false)
}

@Test func propagationRejectsMalformedAndFutureData() throws {
    let now = propagationDate("2026-10-13T14:10:00Z")
    #expect(throws: (any Error).self) { try SpaceWeatherParser.reading(Data("[{\"time_tag\":\"2026-10-14T12:00:00\",\"estimated_kp\":9}]".utf8), field: "estimated_kp", fetchedAt: now) }
    #expect(throws: (any Error).self) { try SpaceWeatherParser.reading(Data("[{\"time_tag\":\"2026-10-13T12:00:00\",\"estimated_kp\":-1}]".utf8), field: "estimated_kp", fetchedAt: now) }
    #expect(throws: (any Error).self) { try SpaceWeatherParser.scales(Data("{\"1\":{\"R\":{\"Scale\":\"5\"}}}".utf8), fetchedAt: now) }
    let text = String(decoding: try weatherFixture("drap.txt"), as: UTF8.self)
    #expect(throws: (any Error).self) { try SpaceWeatherParser.absorption(text.replacingOccurrences(of: "89 |", with: "NaN |"), fetchedAt: now) }
    #expect(throws: (any Error).self) { try SpaceWeatherParser.indices("<html>Error</html>") }
    #expect(RadioLocation(latitude: "NaN", longitude: "0") == nil)
    #expect(RadioLocation(latitude: "-33,45", longitude: "-70,67") != nil)
}

@Test func propagationOfflineKeepsObservationDateAndPartialSources() async throws {
    let now = propagationDate("2026-10-13T14:10:00Z")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    var old = SpaceWeatherSnapshot()
    old.kp = SpaceReading(value: 2, observedAt: now.addingTimeInterval(-3600), fetchedAt: now.addingTimeInterval(-3600))
    old.flux = SpaceReading(value: 120, observedAt: now.addingTimeInterval(-86400), fetchedAt: now.addingTimeInterval(-100))
    let data = try weatherFixture("flux.json")
    let service = SpaceWeatherService(cacheURL: folder.appendingPathComponent("cache.json")) { request in
        #expect(request.url?.query == nil && request.httpBody == nil)
        if request.url == SpaceWeatherSource.flux.url { return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        throw URLError(.notConnectedToInternet)
    }
    let result = await service.download(previous: old, now: now)
    #expect(result.errors.count == 5)
    #expect(result.snapshot.kp?.observedAt == old.kp?.observedAt)
    #expect(result.snapshot.kp?.isFresh(at: now, maxAge: 900) == false)
    #expect(result.snapshot.flux?.value == 123)
    let cached = await service.cached()
    #expect(cached?.kp?.fetchedAt == old.kp?.fetchedAt)
    #expect(cached?.flux?.observedAt == propagationDate("2026-10-12T22:00:00Z"))
}

@Test func propagationDrapUsesActualGridAndWrapsDateLine() throws {
    let text = "# Product Valid At : 2026-10-13 14:04 UTC\n-178 178\n1 | 4 9\n-1 | 2 8\n"
    let grid = try SpaceWeatherParser.absorption(text, fetchedAt: propagationDate("2026-10-13T14:10:00Z"))
    #expect(grid.nearest(to: RadioLocation(latitude: 0.9, longitude: 179)!)?.highestAffectedMHz == 9)
    #expect(grid.nearest(to: RadioLocation(latitude: -0.9, longitude: -179)!)?.highestAffectedMHz == 2)
    #expect(throws: (any Error).self) { try SpaceWeatherParser.absorption(text.replacingOccurrences(of: "4 9", with: "4"), fetchedAt: propagationDate("2026-10-13T14:10:00Z")) }
}

@Test func propagationGeometryAndPowerBudget() throws {
    let origin = RadioLocation(latitude: -33.45, longitude: -70.67)!
    let target = try #require(origin.destination(km: 10_000, bearing: 45))
    #expect(abs(origin.distance(to: target)-10_000) < 0.001)
    #expect(abs(origin.bearing(to: target)-45) < 0.001)
    let high = RadioLocation(latitude: 0, longitude: 0)!.solarElevation(at: propagationDate("2026-03-20T12:00:00Z"))
    let low = RadioLocation(latitude: 0, longitude: 0)!.solarElevation(at: propagationDate("2026-03-20T00:00:00Z"))
    #expect(high > 85 && low < -85)
    #expect(abs(RadioLinkBudget.powerDifference(watts: 200, referenceWatts: 100)! - 3.0103) < 0.0001)
    #expect(RadioLinkBudget.powerDifference(watts: 0, referenceWatts: 100) == nil)
    #expect(abs(RadioLinkBudget.horizonKm(txHeight: 10, rxHeight: 2)! - 18.864) < 0.02)
}

private func referenceInput(watts: Double = 1000, bandwidth: Double = 1000) -> HFPropagationInput {
    HFPropagationInput(origin: RadioLocation(latitude: 49.6666666667, longitude: 6.31666666667)!, target: RadioLocation(latitude: 51.1166666667, longitude: 7.26666666667)!, date: propagationDate("1985-05-15T19:00:00Z"), r12: 18, watts: watts, bandwidth: bandwidth, requiredSNR: 10, txGain: 0, rxGain: 0, noise: 2, frequencyMHz: 6.1)
}
@Test func propagationMatchesPublishedITURReferenceNoise() async throws {
    let report = try await HFPropagationEngine().predict(referenceInput())
    let sample = try #require(report.hourly.first(where: { $0.hour == 19 }))
    // ITURHFProp/Bin/1-5-85.out, columns distance and noise figures, published by the model authors.
    #expect(abs(sample.distanceKm-174.728941) < 0.0001)
    #expect(abs(try #require(sample.noiseFactorDB)-51.31) < 0.01)
    #expect(abs(try #require(sample.atmosphericNoiseDB)-49.90) < 0.01)
    #expect(abs(try #require(sample.manMadeNoiseDB)-45.45) < 0.01)
    #expect(abs(try #require(sample.galacticNoiseDB)-33.94) < 0.01)
    #expect(report.bands.count == 10 && report.hourly.count == 24 && report.reach.count == 15)
    #expect(report.predictions.allSatisfy { $0.isValid })
}

@Test func propagationPowerAndBandwidthHavePhysicalScaling() async throws {
    let engine = HFPropagationEngine()
    let reference = try await engine.predict(referenceInput())
    let stronger = try await engine.predict(referenceInput(watts: 10_000))
    let wider = try await engine.predict(referenceInput(bandwidth: 2000))
    let a = try #require(reference.hourly.first(where: { $0.hour == 19 }))
    let b = try #require(stronger.hourly.first(where: { $0.hour == 19 }))
    let c = try #require(wider.hourly.first(where: { $0.hour == 19 }))
    #expect(abs(try #require(b.snrDB)-#require(a.snrDB)-10) < 0.001)
    #expect(abs(try #require(b.receivedDBm)-#require(a.receivedDBm)-10) < 0.001)
    #expect(try #require(b.reliability) >= #require(a.reliability))
    #expect(abs(try #require(c.snrDB)-#require(a.snrDB)+3.0103) < 0.001)
}

@Test func propagationInvalidInputAndCancelledCalculation() async throws {
    #expect(!referenceInput(watts: 0).isValid)
    await #expect(throws: (any Error).self) { try await HFPropagationEngine().predict(referenceInput(watts: 0)) }
    let task = Task { try await HFPropagationEngine().predict(referenceInput()) }
    task.cancel()
    await #expect(throws: (any Error).self) { try await task.value }
}
