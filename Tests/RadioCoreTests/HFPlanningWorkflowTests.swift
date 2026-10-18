import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private func planningEntry(site: String = "tx", frequency: Double = 9655, raw: String = "test-transmission") -> BroadcastEntry {
    .init(frequencyKHz: frequency, time: "0300-0400", days: "1234567", country: "TST", station: "Radio de prueba", language: "E", target: "SAm", site: site, persistence: 1, startDate: "", stopDate: "", raw: raw)
}
@MainActor private func planningGuide(entry: BroadcastEntry, reference: BroadcastReference = .init()) -> BroadcastStore {
    let store = BroadcastStore()
    store.snapshot = .init(entries: [entry], reference: reference, season: "a26", sourceURL: URL(string: "https://example.org/schedule.csv")!, fetchedAt: Date(), sourceModifiedAt: nil, skippedRows: 0)
    store.selectedID = entry.id
    return store
}

@Test @MainActor func hfGuideSelectionSurvivesTableDetachingAndCopiesPartialData() throws {
    let entry = planningEntry(site: "unknown"), guide = planningGuide(entry: entry)
    guide.selectedID = nil // navigation can clear the table binding
    #expect(guide.selectedEntry?.id == entry.id)
    let store = PropagationStore(); store.targetLatitude = "50"; store.targetLongitude = "10"; store.watts = "100000"
    #expect(store.useSelectedStation(guide))
    #expect(store.frequencyMHz == "9.655" && store.listening)
    #expect(store.targetName.contains(entry.station))
    #expect(store.targetLatitude.isEmpty && store.targetLongitude.isEmpty && store.watts.isEmpty)
    let missing = store.inputProblems(origin: RadioLocation(latitude: -33.45, longitude: -70.67), date: Date())
    #expect(missing.contains { $0.contains("Emisor remoto") })
    #expect(missing.contains { $0.contains("Potencia TX") })
    #expect(!store.stationTransferNotice.isEmpty)
}

@Test @MainActor func hfGuideHandoffUsesPhysicalTransmitterAndKeepsTXRXRoles() throws {
    let entry = planningEntry()
    var reference = BroadcastReference(); reference.sites["TST|tx"] = .init(name: "Emisor de prueba", latitude: 40, longitude: -4)
    let guide = planningGuide(entry: entry, reference: reference), store = PropagationStore()
    store.useStation(entry, guide: guide)
    store.watts = " 100000 "; store.r12 = "0"
    let local = try #require(RadioLocation(latitude: " −33,45 ", longitude: " −70,67 "))
    let input = try #require(store.input(origin: local, date: Date()))
    #expect(input.isValid && input.r12 == 0 && input.watts == 100000)
    #expect(input.origin.latitude == 40 && input.target == local)
    #expect(input.bandwidth == 9000 && input.frequencyMHz == 9.655)
    let text = store.hfPlanningDataText(origin: local, date: Date(timeIntervalSince1970: 0))
    #expect(text.contains("TX: 40.00000, -4.00000") && text.contains("RX: -33.45, -70.67") && text.contains("1970-01-01T00:00:00Z"))
    store.listening = false
    #expect(store.input(origin: local, date: Date())?.origin == local)
}

@Test @MainActor func hfMultipleTransmitterSitesRequireAnExplicitChoice() throws {
    let entry = planningEntry(site: "a,b")
    var ref = BroadcastReference()
    ref.sites["TST|a"] = .init(name: "Primer sitio", latitude: 20, longitude: 30)
    ref.sites["TST|b"] = .init(name: "Segundo sitio", latitude: 40, longitude: 50)
    let store = PropagationStore(); store.useStation(entry, guide: planningGuide(entry: entry, reference: ref))
    #expect(store.stationSites.count == 2 && store.selectedStationSite == nil && store.targetLatitude.isEmpty)
    store.selectedStationSite = 1; store.useChosenStationSite()
    #expect(Double(store.targetLatitude) == 40 && Double(store.targetLongitude) == 50)
}

@Test @MainActor func hfCandidatePowerIsAnExplicitAssumptionAndTracksManualChanges() {
    let store = PropagationStore()
    store.stationPowerCandidate = .init(frequencyKHz: 9655, startUTC: "0300", stopUTC: "0400", targetArea: "13", siteCode: "TST", powerKW: 250, azimuthDegrees: 90, days: "1234567", startDate: "290326", stopDate: "251026", modulationCode: "D", language: "Eng", broadcasterCode: "TST", managerCode: "TST", raw: "candidate")
    store.useCandidatePowerAsAssumption()
    #expect(store.watts == "250000" && store.wattsSource.contains("Supuesto elegido"))
    store.watts = "50000"
    #expect(store.wattsSource.contains("manualmente"))
}

@Test func hfFrequencyCopiesKeepExplicitUnitsAndDoNotGuessUnitlessKHz() {
    #expect(RadioNumericText.frequencyMHz(" 9655 kHz ") == 9.655)
    #expect(RadioNumericText.frequencyMHz("9,655 MHz") == 9.655)
    #expect(RadioNumericText.frequencyMHz("9655000 Hz").map { abs($0 - 9.655) < 1e-10 } == true)
    #expect(RadioNumericText.frequencyMHz("9655") == 9655)
    #expect(RadioNumericText.frequencyMHz("NaN MHz") == nil)
}

@Test @MainActor func hfSelectedPlanningTimeAndR12ZeroReachTheCalculation() async throws {
    let store = PropagationStore()
    let date = try #require(ISO8601DateFormatter().date(from: "1985-05-15T19:00:00Z"))
    store.planningDate = date; store.usesCurrentPlanningTime = false
    #expect(store.planningTime(at: Date()) == date)
    store.targetLatitude = "51.1166666667"; store.targetLongitude = "7.26666666667"
    store.frequencyMHz = "6100 kHz"; store.watts = "1000"; store.bandwidth = "1000"; store.r12 = "0"
    let origin = try #require(RadioLocation(latitude: 49.6666666667, longitude: 6.31666666667))
    #expect(store.inputProblems(origin: origin, date: date).isEmpty)
    let input = try #require(store.input(origin: origin, date: date))
    let report = try await HFPropagationEngine().predict(input)
    #expect(report.hourUTC == 19 && report.hourly.count == 24 && report.input.r12 == 0)
}

@Test func hfITUIndexParserKeepsSolarMinimumZero() throws {
    let rows = (1...12).map { month in "<tr>" + (month == 1 ? "<td>2026</td>" : "") + "<td>\(month)</td><td>99</td><td>0</td><td>0</td><td>0</td></tr>" }.joined()
    let html = "<table>R12\(rows)</table>"
    let indices = try SpaceWeatherParser.indices(html)
    #expect(indices.count == 12 && indices.allSatisfy { $0.r12 == 0 })
}

@Test @MainActor func hfAutomaticR12CannotSilentlyFollowTheWrongPlanningMonth() {
    let store = PropagationStore()
    let formatter = ISO8601DateFormatter()
    let october = formatter.date(from: "2026-10-18T12:00:00Z")!
    let november = formatter.date(from: "2026-11-18T12:00:00Z")!
    store.weather.indices = [IonosphericIndex(year: 2026, month: 10, r12: 75, predicted: false)]
    store.useITUIndex(at: october)
    #expect(!store.r12MonthMismatch(at: october))
    #expect(store.r12MonthMismatch(at: november))
    #expect(store.inputProblems(origin: nil, date: november).contains { $0.contains("2026-10") })
    store.useITUIndex(at: november) // No November entry: never reuse October silently.
    #expect(store.r12MonthMismatch(at: november))
    store.useManualR12()
    #expect(!store.r12MonthMismatch(at: november) && RadioNumericText.number(store.r12) == 75)
    store.weather.indices.append(IonosphericIndex(year: 2026, month: 11, r12: 100, predicted: true))
    store.useITUIndex(at: november)
    #expect(!store.r12MonthMismatch(at: november) && store.r12 == "100.0")
}
