import Foundation
import Testing
@testable import RadioCore

private func bandDate(_ text: String) -> Date { SpaceWeatherParser.date(text)! }
private func bandFixture() throws -> Data { try Data(contentsOf: Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("SpaceWeather/hamqsl.xml")) }

@Test func bandInformationParsesProviderAndPreservesRegions() throws {
    let result = try BandInformationParser.parse(bandFixture(), fetchedAt: bandDate("2026-10-13T15:00:00Z"))
    #expect(result.bands.count == 4)
    #expect(result.bands[0].day == .poor && result.bands[0].night == .fair)
    #expect(result.bands[1].day == .good && result.bands[1].night == .good)
    #expect(result.updatedAt == bandDate("2026-10-13T14:42:00Z"))
    #expect(result.vhf.count == 5)
    #expect(result.vhf.first?.region == "northern_hemi")
    #expect(result.vhf.contains { $0.region == "north_america" })
    #expect(!result.isFresh(at: bandDate("2026-10-14T00:00:00Z")))
}

@Test func bandInformationRejectsEntitiesMalformedAndFutureData() throws {
    let fixture = String(decoding: try bandFixture(), as: UTF8.self)
    let now = bandDate("2026-10-13T15:00:00Z")
    #expect(throws: (any Error).self) { try BandInformationParser.parse(Data("<!DOCTYPE solar [<!ENTITY x SYSTEM 'file:///tmp/private'>]><solar>&x;</solar>".utf8), fetchedAt: now) }
    #expect(throws: (any Error).self) { try BandInformationParser.parse(Data(fixture.replacingOccurrences(of: "1442 GMT", with: "1642 GMT").utf8), fetchedAt: now) }
    #expect(throws: (any Error).self) { try BandInformationParser.parse(Data(fixture.replacingOccurrences(of: ">Good<", with: ">Unknown<").utf8), fetchedAt: now) }
    #expect(throws: (any Error).self) { try BandInformationParser.parse(Data(fixture.dropLast(30).utf8), fetchedAt: now) }
}

private actor BandQueryCounter {
    var count = 0
    func add() { count += 1 }
}
@Test func bandInformationHourlyCadenceIncludesManualRefreshAndRestarts() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = dir.appendingPathComponent("weather.json"), counter = BandQueryCounter(), data = try bandFixture()
    let transport: SpaceWeatherService.Transport = { request in
        if request.url == SpaceWeatherSource.bandInformation.url {
            await counter.add()
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        throw URLError(.notConnectedToInternet)
    }
    let now = bandDate("2026-10-13T15:00:00Z"), service = SpaceWeatherService(cacheURL: cache, transport: transport)
    let first = await service.download(now: now)
    #expect(first.snapshot.bandInformation != nil)
    let second = await service.download(previous: first.snapshot, now: now.addingTimeInterval(180), forceIndices: true)
    #expect(!second.attemptedSources.contains("bandInformation"))
    #expect(await counter.count == 1)
    let restart = SpaceWeatherService(cacheURL: cache, transport: transport)
    _ = await restart.download(now: now.addingTimeInterval(600), forceIndices: true)
    #expect(await counter.count == 1)
    _ = await restart.download(now: now.addingTimeInterval(3600))
    #expect(await counter.count == 2)
}

@Test func bandInformationChangeAlertsDoNotRepeatOldDates() throws {
    let base = try BandInformationParser.parse(bandFixture(), fetchedAt: bandDate("2026-10-13T15:00:00Z"))
    let row = base.bands[0]
    let rows = [BandInformation(name: row.name, day: .good, night: row.night)] + base.bands.dropFirst()
    let new = BandInformationSnapshot(bands: Array(rows), vhf: base.vhf, updatedAt: base.updatedAt.addingTimeInterval(3600), fetchedAt: base.fetchedAt.addingTimeInterval(3600))
    #expect(new.changes(from: base).count == 1)
    #expect(base.changes(from: new).isEmpty)
    #expect(new.changes(from: new).isEmpty)
}

@Test func bandContactDistanceAndInternationalAreIndependent() {
    #expect(RadioContactDistance.classify(km: 50) == .nearby)
    #expect(RadioContactDistance.classify(km: 500) == .regional)
    #expect(RadioContactDistance.classify(km: 2500) == .distant)
    #expect(RadioContactDistance.classify(km: 6000) == .dx)
    #expect(RadioContactDistance.classify(km: .nan) == nil)
    #expect(RadioContactDistance.international(originCountry: "CL", targetCountry: "AR") == true)
    #expect(RadioContactDistance.international(originCountry: "cl", targetCountry: " CL ") == false)
    #expect(RadioContactDistance.international(originCountry: "", targetCountry: "ES") == nil)
    #expect(RadioContactDistance.international(originCountry: "Chile", targetCountry: "ZZ") == nil)
}
