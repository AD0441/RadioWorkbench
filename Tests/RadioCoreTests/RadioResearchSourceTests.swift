import Foundation
import Testing
@testable import RadioCore

private func researchDateUTC(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private func hfccRow(frequency: Int = 9_655, start: String = "0330", stop: String = "0345", language: String = "Eng", modulation: String = "D", power: Int = 250) -> String {
    var bytes = [UInt8](repeating: 32, count: 158)
    func put(_ value: String, _ columns: ClosedRange<Int>, right: Bool = false) {
        let payload = Array(value.utf8)
        let width = columns.count
        let offset = columns.lowerBound - 1 + (right ? max(0, width - payload.count) : 0)
        for (index, byte) in payload.prefix(width).enumerated() { bytes[offset + index] = byte }
    }
    put(String(format: "%5d", frequency), 1...5)
    put(start, 7...10)
    put(stop, 12...15)
    put("42-44", 17...46)
    put("TAS", 48...50)
    put(String(format: "%4d", power), 52...55)
    put("225", 57...63, right: true)
    put("1234567", 73...79)
    put("290326", 81...86)
    put("251026", 88...93)
    put(modulation, 95...95)
    put(language, 103...112)
    put("USA", 114...116)
    put("TWR", 118...120)
    put("ENC", 122...124)
    return String(decoding: bytes, as: UTF8.self)
}

@Test func hfccFixedWidthScheduleKeepsDeclaredPowerDirectionAndMode() throws {
    let url = URL(string: "https://new.hfcc.org/data/a26/a26allx2.zip")!
    let snapshot = try HFCCScheduleParser.parse(hfccRow(), season: "a26", sourceURL: url, fetchedAt: Date())
    let tx = try #require(snapshot.transmissions.first)
    #expect(tx.frequencyKHz == 9_655)
    #expect(tx.startUTC == "0330" && tx.stopUTC == "0345")
    #expect(tx.powerKW == 250 && tx.scheduledPowerWatts == 250_000)
    #expect(tx.azimuthDegrees == 225)
    #expect(tx.targetArea == "42-44")
    #expect(tx.modulation == "AM · DSB (HFCC)")
}

@Test func hfccMatchRejectsAmbiguousRowsAndUsesLanguageWhenUnique() throws {
    let url = URL(string: "https://new.hfcc.org/data/a26/a26allx2.zip")!
    let parsed = try HFCCScheduleParser.parse([hfccRow(language: "Eng"), hfccRow(language: "Por", power: 100)].joined(separator: "\n"), season: "a26", sourceURL: url, fetchedAt: Date())
    let entry = BroadcastEntry(frequencyKHz: 9_655, time: "0330-0345", days: "1234567", country: "TWR", station: "TWR Test", language: "Eng", target: "SAm", site: "tas", persistence: 1, startDate: "", stopDate: "", raw: "eibi")
    #expect(parsed.match(for: entry)?.powerKW == 250)
    let ambiguous = try HFCCScheduleParser.parse([hfccRow(language: "Eng"), hfccRow(language: "Eng", power: 100)].joined(separator: "\n"), season: "a26", sourceURL: url, fetchedAt: Date())
    #expect(ambiguous.match(for: entry) == nil)
}

@Test func maidenheadGridFourIsValidAndUsesFourCharacterResolution() {
    #expect(Maidenhead.grid4(latitude: -33.45, longitude: -70.67) == "FF46")
    #expect(Maidenhead.grid4(latitude: 90, longitude: 180) == "RR99")
    #expect(Maidenhead.grid4(latitude: 90.1, longitude: 0) == nil)
    let center = Maidenhead.center("FF46")
    #expect(center.map { abs($0.latitude + 33.5) < 0.01 && abs($0.longitude + 71) < 0.01 } == true)
    #expect(Maidenhead.center("ZZ99") == nil)
    #expect(PSKReporterParser.isGrid4("ff46"))
    #expect(!PSKReporterParser.isGrid4("ZZ99"))
}

@Test func reverseBeaconLinesParseSpotsAndRejectPrompts() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let spot = try #require(RBNParser.parse("DX de W3LPL-#: 14025.1 K1ABC CW 23 dB 30 WPM CQ", receivedAt: now))
    #expect(spot.spotter == "W3LPL-#")
    #expect(spot.callsign == "K1ABC")
    #expect(spot.frequencyKHz == 14_025.1)
    #expect(spot.band == "20 m")
    #expect(spot.mode == "CW" && spot.snrDB == 23 && spot.speedWPM == 30)
    #expect(spot.comment == "CQ")
    #expect(RBNParser.parse("Welcome to the Reverse Beacon Network") == nil)
    #expect(RBNParser.parse("DX de BAD: 999999 K1ABC CW 20 dB") == nil)
    #expect(RBNParser.validLogin(" ce1abc ") == "CE1ABC")
    #expect(RBNParser.validLogin("some user") == nil)
}

@Test func reverseBeaconTelnetDecoderHandlesNegotiationAndSplitLines() {
    var decoder = RBNTelnetDecoder()
    let first = decoder.consume(Data([255, 251, 1] + Array("DX de W3LPL-#: 14025.1 K1ABC CW".utf8)))
    #expect(first.lines.isEmpty)
    #expect(first.replies == [255, 254, 1])
    let second = decoder.consume(Data(Array(" 23 dB 30 WPM CQ\r\n".utf8)))
    #expect(second.lines == ["DX de W3LPL-#: 14025.1 K1ABC CW 23 dB 30 WPM CQ"])
    #expect(second.replies.isEmpty)
}

@Test func terrainProfileSamplesRouteAndParsesOpenMeteoElevation() throws {
    let start = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let end = try #require(start.destination(km: 120, bearing: 100))
    let locations = try TerrainProfileGeometry.sampleLocations(from: start, to: end)
    #expect(locations.count == 241)
    #expect(locations.first == start)
    #expect((locations.last?.distance(to: end) ?? 10) < 0.001)
    #expect(TerrainProfileGeometry.maximumBatchSize == 100)
    let heights = (0..<locations.count).map { Double(400 + $0) }
    let json = try JSONSerialization.data(withJSONObject: ["elevation": heights])
    let profile = try TerrainElevationParser.parse(json, locations: locations, fetchedAt: Date(timeIntervalSince1970: 100))
    #expect(profile.points.count == 241)
    #expect(abs(profile.resolutionMeters - 500) < 0.01)
    #expect(profile.terrainReliefMeters == 240)
    #expect(profile.points.last?.elevationMeters == 640)
    #expect(profile.antennaAltitudeAMSL(aglMeters: 12, atOrigin: true) == 412)
    #expect(profile.antennaAltitudeAMSL(aglMeters: 12, atOrigin: false) == 652)
    let tooLong = try #require(start.destination(km: 600, bearing: 90))
    #expect(throws: TerrainProfileError.self) { try TerrainProfileGeometry.sampleLocations(from: start, to: tooLong) }
    #expect(throws: TerrainProfileError.self) { try TerrainElevationParser.parse(Data("{\"elevation\":[1]}".utf8), locations: locations) }
}

@Test func terrainMapFresnelCorridorTracksPathAndFrequency() throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let destination = try #require(origin.destination(km: 30, bearing: 80))
    let midpoint = try #require(origin.destination(km: 15, bearing: 80))
    let lowFrequency = TerrainLinkGeometry.firstFresnelCorridor(from: origin, to: destination, frequencyMHz: 144)
    let highFrequency = TerrainLinkGeometry.firstFresnelCorridor(from: origin, to: destination, frequencyMHz: 430)
    #expect(lowFrequency.count == 66)
    #expect((lowFrequency.first?.distance(to: origin) ?? 1) < 0.001)
    #expect((lowFrequency[16].distance(to: midpoint) * 1_000) > 50)
    #expect((highFrequency[16].distance(to: midpoint)) < lowFrequency[16].distance(to: midpoint))
    #expect(TerrainLinkGeometry.firstFresnelCorridor(from: origin, to: destination, frequencyMHz: 7.1).isEmpty)
}

@Test func terrainCoverageEnvelopeUses32DirectionalRanges() throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    var ranges = Array(repeating: 50.0, count: TerrainCoverageGeometry.bearingCount)
    ranges[3] = 0
    let boundary = TerrainCoverageGeometry.boundary(from: origin, reachByBearingKm: ranges)
    #expect(boundary.count == 33)
    #expect(boundary.first == origin)
    #expect(abs((boundary[1].distance(to: origin)) - 50) < 0.001)
    #expect(TerrainCoverageGeometry.boundary(from: origin, reachByBearingKm: [50, 40]).isEmpty)
    #expect(TerrainCoverageGeometry.boundary(from: origin, reachByBearingKm: Array(repeating: 0, count: TerrainCoverageGeometry.bearingCount)).isEmpty)
}

@Test func terrainLineOfSightCombinesAGLWithTerrainAndDetectsMountainWalls() throws {
    let origin = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let target = try #require(origin.destination(km: 10, bearing: 90))
    let middle = try #require(origin.destination(km: 5, bearing: 90))
    let points = [TerrainPoint(location: origin, elevationMeters: 100),
                  TerrainPoint(location: middle, elevationMeters: 500),
                  TerrainPoint(location: target, elevationMeters: 150)]
    let profile = TerrainProfile(origin: origin, target: target, points: points,
                                 fetchedAt: Date(timeIntervalSince1970: 100), resolutionMeters: 5_000)
    let result = try #require(TerrainLineOfSight.evaluate(profile: profile, txHeightAGLMeters: 20, rxHeightAGLMeters: 30))
    #expect(result.txAntennaAltitudeAMSL == 120)
    #expect(result.rxAntennaAltitudeAMSL == 180)
    #expect(!result.isClear)
    #expect(result.minimumClearanceMeters < -300)
    #expect(abs(result.minimumClearanceDistanceKm - 5) < 0.01)
    #expect(result.apparentTerrainAltitudeAMSL[1] > 500)
}

@Test func terrainITMInputValidatesVHFModelRangeAndRadioBudget() {
    let input = TerrainITMInput(frequencyMHz: 144.39, txHeightMeters: 10, rxHeightMeters: 2, transmitWatts: 10)
    #expect(input.isValid)
    #expect(!TerrainITMInput(frequencyMHz: 7.1, txHeightMeters: 10, rxHeightMeters: 2).isValid)
    #expect(!TerrainITMInput(frequencyMHz: 144, txHeightMeters: 0, rxHeightMeters: 2).isValid)
}

@Test func noaaThreeDayForecastParsesKpAndStormProbabilityTables() throws {
    let source = """
    :Product: 3-Day Forecast
    :Issued: 2026 Oct 14 0030 UTC
    # Prepared by NOAA
    A. NOAA Geomagnetic Activity Observation and Forecast
    The greatest observed 3 hr Kp over the past 24 hours was 3.
    NOAA Kp index breakdown Oct 14-Oct 16 2026
                 Oct 14       Oct 15       Oct 16
    00-03UT       3.67         2.67         1.67
    03-06UT       3.33         3.33         1.67
    06-09UT       3.67         3.00         1.33
    09-12UT       2.67         2.33         1.33
    12-15UT       2.67         1.67         1.33
    15-18UT       3.33         1.00         1.33
    18-21UT       3.33         1.33         1.67
    21-00UT       3.33         2.33         1.33
    Rationale: No G1 (Minor) or greater geomagnetic storms are expected.

    B. NOAA Solar Radiation Activity Observation and Forecast
    Solar Radiation Storm Forecast for Oct 14-Oct 16 2026
                  Oct 14  Oct 15  Oct 16
    S1 or greater    5%      1%      1%
    Rationale: No S1 or greater solar radiation storms are expected.

    C. NOAA Radio Blackout Activity and Forecast
    Radio Blackout Forecast for Oct 14-Oct 16 2026
                  Oct 14        Oct 15        Oct 16
    R1-R2           10%           10%           10%
    R3 or greater    1%            1%            1%
    Rationale: No R1 radio blackouts are expected.
    """
    let forecast = try NoaaThreeDayForecastParser.parse(Data(source.utf8), fetchedAt: researchDateUTC("2026-10-14T00:35:00Z"))
    #expect(forecast.datesUTC == [researchDateUTC("2026-10-14T00:00:00Z"), researchDateUTC("2026-10-15T00:00:00Z"), researchDateUTC("2026-10-16T00:00:00Z")])
    #expect(forecast.dailyMaximumKp == [3.67, 3.33, 1.67])
    #expect(forecast.s1OrGreaterProbability == [5, 1, 1])
    #expect(forecast.r1ToR2Probability == [10, 10, 10])
    #expect(forecast.r3OrGreaterProbability == [1, 1, 1])
    #expect(forecast.blackoutRationale.contains("No R1"))
}

@Test func pskReporterXMLParsesRecentReportsAndRejectsOldOrInvalidRows() throws {
    let now = Date()
    let recent = Int(now.timeIntervalSince1970 - 120)
    let old = Int(now.timeIntervalSince1970 - 90_000)
    let xml = """
    <receptionReports>
      <receptionReport receiverCallsign="CE1ABC" receiverLocator="FF46" senderCallsign="LU1XYZ" senderLocator="GF05" frequency="14074000" mode="FT8" flowStartSeconds="\(recent)" />
      <receptionReport receiverCallsign="CE1ABC" receiverLocator="FF46" senderCallsign="LU2OLD" frequency="14074000" flowStartSeconds="\(old)" />
      <receptionReport receiverCallsign="CE1ABC" receiverLocator="FF46" senderCallsign="!bad" frequency="14074000" flowStartSeconds="\(recent)" />
    </receptionReports>
    """
    let snapshot = try PSKReporterParser.parse(Data(xml.utf8), grid: "FF46", fetchedAt: now)
    #expect(snapshot.spots.count == 1)
    #expect(snapshot.spots.first?.senderCallsign == "LU1XYZ")
    #expect(snapshot.spots.first?.frequencyKHz == 14_074)
    #expect(snapshot.spots.first?.mode == "FT8")
    #expect(snapshot.spots.first?.senderLocator == "GF05")
}

@Test func ionosondeParserRetainsStationCoordinatesConfidenceAndObservationTime() throws {
    let now = Date(), stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-900))
    let json = """
    [
      {"time":"\(stamp)","fof2":7.5,"mufd":13.2,"hmf2":302.0,"cs":88,
       "station":{"code":"RL052","name":"Santiago Test","latitude":"-33.45","longitude":"289.33"}},
      {"time":"\(stamp)","fof2":6.4,"mufd":11.8,"cs":-1,
       "station":{"code":"RL053","name":"Distant Test","latitude":"-20","longitude":"-60"}},
      {"time":"2000-01-01T00:00:00Z","fof2":5.0,"mufd":10.0,"station":{"code":"OLD","name":"Old","latitude":0,"longitude":0}}
    ]
    """
    let snapshot = try IonosondeParser.parse(Data(json.utf8), fetchedAt: now)
    #expect(snapshot.observations.count == 2)
    let santiago = try #require(snapshot.observations.first(where: { $0.code == "RL052" }))
    #expect(abs(santiago.longitude + 70.67) < 0.000001)
    #expect(santiago.fof2MHz == 7.5 && santiago.muf3000MHz == 13.2)
    #expect(santiago.confidence == 88)
    let home = try #require(RadioLocation(latitude: -33.45, longitude: -70.67))
    let nearest = snapshot.nearest(to: home)
    #expect(nearest.first?.0.code == "RL052")
    #expect((nearest.first?.1 ?? 100) < 0.001)
}

private actor PSKRequestCount {
    var count = 0
    func increment() { count += 1 }
}

@Test func pskReporterServiceHonorsFiveMinuteQueryCadence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(), epoch = Int(now.timeIntervalSince1970 - 60)
    let xml = Data("<receptionReports><receptionReport receiverCallsign=\"CE1ABC\" receiverLocator=\"FF46\" senderCallsign=\"LU1XYZ\" frequency=\"14074000\" flowStartSeconds=\"\(epoch)\" /></receptionReports>".utf8)
    let counter = PSKRequestCount()
    let service = PSKReporterService(cacheURL: directory.appendingPathComponent("spots.json"), transport: { request in
        await counter.increment()
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "receiverCallsign", value: "FF46")) == true)
        return (xml, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    _ = try await service.download(grid: "FF46", now: now)
    let cached = try await service.download(grid: "FF46", now: now.addingTimeInterval(180))
    #expect(cached.fetchedAt == now)
    do {
        _ = try await service.download(grid: "FF47", now: now.addingTimeInterval(180))
        Issue.record("A changed grid should respect the API's five-minute query interval")
    } catch is PSKReporterError { }
    #expect(await counter.count == 1)
}
