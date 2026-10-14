import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

@MainActor @Test func aprsCallsignTextFieldNormalizesWithoutRecursiveSetter() {
    let key = "aprsISCallsign"
    let defaults = UserDefaults.standard
    let previousValue = defaults.string(forKey: key)
    defer {
        if let previousValue { defaults.set(previousValue, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    let store = APRSISStore()
    store.callsign = "c"
    store.callsign = "ce3"
    store.callsign = "ce3abc"
    #expect(store.callsign == "CE3ABC")
    #expect(defaults.string(forKey: key) == "CE3ABC")
}

@Test func chileBandLookupMatchesPublishedAmateurSegmentsAndLeavesOtherServicesUnclassified() {
    let vhf = ChileBandAllocation.matches(144.39)
    #expect(vhf.contains { $0.lowerMHz == 144 && $0.upperMHz == 146 && $0.status == "Primario" })
    #expect(ChileBandAllocation.matches(7.074).contains { $0.lowerMHz == 7 && $0.upperMHz == 7.1 })
    #expect(ChileBandAllocation.matches(162.55).isEmpty)
    #expect(ChileBandAllocation.matches(.nan).isEmpty)
}

@Test func aprsParserReadsUncompressedPositionAndRejectsBadCoordinates() throws {
    let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let position = try #require(APRSPositionParser.parse("CE3ABC-9>APRS,WIDE1-1:!3345.00S/07040.20W>móvil", receivedAt: receivedAt))
    #expect(position.id == "CE3ABC-9")
    #expect(abs(position.latitude + 33.75) < 0.0001)
    #expect(abs(position.longitude + 70.67) < 0.0001)
    #expect(position.symbol == "/>")
    #expect(position.comment == "móvil")
    #expect(position.path == "APRS,WIDE1-1")
    #expect(position.receivedAt == receivedAt)
    let compressed = try #require(APRSPositionParser.parse("CE3XYZ>APRS:!/!!!!!!!!!"))
    #expect(compressed.latitude == 90 && compressed.longitude == -180)
    #expect(APRSPositionParser.parse("CE3ABC>APRS:!9960.00N/18100.00E>bad") == nil)
    #expect(APRSPositionParser.parse("CE3ABC>APRS:>status only") == nil)
}

@Test func subtelRepeaterRowsTolerateSpanishHeadersAndNormalizeFrequency() throws {
    let records = SUBTELRepeaterParser.parse(rows: [
        ["Indicativo", "Región", "Comuna", "Frecuencia RX", "Frecuencia TX", "Tono CTCSS", "Latitud", "Longitud"],
        ["CE3ABC", "Metropolitana", "Santiago", "144,390", "144,990", "123,0", "-33,45", "-70,67"],
        ["CE5DEF", "Biobío", "Concepción", "145000000", "145600000", "", "", ""],
        ["", "", "", "", "", "", "", ""]
    ])
    let repeater = try #require(records.first)
    #expect(repeater.id == "CE3ABC")
    #expect(repeater.receiveMHz == 144.39)
    #expect(repeater.transmitMHz == 144.99)
    #expect(repeater.toneHz == 123)
    #expect(repeater.latitude == -33.45 && repeater.longitude == -70.67)
    #expect(records.last?.receiveMHz == 145 && records.last?.transmitMHz == 145.6)
}

@Test func subtelCallsignParserKeepsLicenseFieldsAndExcludesNames() throws {
    let rows = SUBTELCallsignParser.parse("""
    Licencia Señal Distintiva Nombre Región Comuna Fecha Vencimiento
    7426-8 CE3ABC PERSONA DE PRUEBA Región Metropolitana de Santiago Ñuñoa 30/06/2027
    """, category: "General")
    let row = try #require(rows.first)
    #expect(row.id == "CE3ABC")
    #expect(row.category == "General")
    #expect(row.expiresOn == "30/06/2027")
    #expect(!row.region.contains("PERSONA"))
}

@Test func satelliteElevationAndPassPredictionStayWithinPhysicalRanges() throws {
    let epoch = ISO8601DateFormatter().date(from: "2026-10-14T00:00:00Z")!
    let orbit = TLEOrbit(name: "Test LEO", catalogNumber: 99999, epoch: epoch, meanMotionRevolutionsPerDay: 15.5,
                         eccentricity: 0.001, inclinationDegrees: 51.6, raanDegrees: 12, argumentOfPerigeeDegrees: 50, meanAnomalyDegrees: 180)
    let elevation = try #require(orbit.elevationDegrees(at: epoch, latitude: -33.45, longitude: -70.67))
    #expect((-90...90).contains(elevation))
    let passes = SatellitePassPredictor.passes(orbit: orbit, latitude: -33.45, longitude: -70.67, from: epoch, hours: 24, stepSeconds: 30)
    #expect(passes.allSatisfy { $0.maximumElevation >= 5 && $0.maximumElevation <= 90 && $0.aos <= $0.maximumAt && $0.maximumAt <= $0.los })
}
