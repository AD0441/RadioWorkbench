import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

@Test(arguments: [0.0,-1.0,Double.nan,Double.infinity,Double.greatestFiniteMagnitude,Double.leastNonzeroMagnitude])
func spectrumRejectsInvalidRatesWithoutIntegerTraps(_ rate: Double) {
    let frame = SpectrumAnalyzer().analyze([0,0.1,-0.1], sampleRate: rate)
    #expect(frame.bins.isEmpty && frame.sampleRate == 0 && frame.upperFrequency == 0)
    #expect(frame.levelDB.isFinite && frame.peakFrequency == 0)
}

@Test(arguments: [Int?.none, -1, 101])
func absentOrInvalidForecastProbabilityIsUnknown(_ value: Int?) {
    #expect(WorkbenchFormatting.probability(value, locale: Locale(identifier: "en")) == "—")
}

@Test func forecastFormattingUsesTheSelectedLanguageAndUTCDate() throws {
    let date = try #require(ISO8601DateFormatter().date(from: "2026-10-28T00:30:00Z"))
    #expect(WorkbenchFormatting.utcDay(date, locale: Locale(identifier: "en_US")).contains("Wednesday"))
    #expect(WorkbenchFormatting.utcDay(date, locale: Locale(identifier: "es_CL")).contains("miércoles"))
    #expect(WorkbenchFormatting.probability(0, locale: Locale(identifier: "en_US")) == "0%")
    #expect(WorkbenchFormatting.probability(100, locale: Locale(identifier: "en_US")) == "100%")
}

@Test @MainActor func palettePersistenceDoesNotInvalidateExistingPreferences() throws {
    let suite = "RAZIEL-palette-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var previous = WorkbenchPreferences(); previous.language = "en"; previous.waterfallFPS = 10
    defaults.set(try JSONEncoder().encode(previous), forKey: "Workbench.preferences.v1")
    let store = AppPreferencesStore(defaults: defaults)
    #expect(store.values == previous && store.colorPalette == .graphite)
    store.colorPalette = .forest
    let restored = AppPreferencesStore(defaults: defaults)
    #expect(restored.colorPalette == .forest && restored.values == previous)
    defaults.set("invalid-palette", forKey: "Workbench.colorPalette.v1")
    #expect(AppPreferencesStore(defaults: defaults).colorPalette == .graphite)
}

@Test func incompleteNOAAKpDoesNotInventAZero() {
    let incomplete = NoaaThreeDayForecast(issuedAt: .distantPast, fetchedAt: .distantPast, datesUTC: [],
        kpByThreeHour: Array(repeating: [], count: 8), s1OrGreaterProbability: [], r1ToR2Probability: [], r3OrGreaterProbability: [],
        geomagneticRationale: "", solarRationale: "", blackoutRationale: "")
    #expect(incomplete.dailyMaximumKp.isEmpty)
}
