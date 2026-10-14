import Foundation
import Testing
@testable import RadioCore

private func dateUTC(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private func entry(time: String = "0000-2400", days: String = "", persistence: Int = 1, start: String = "", stop: String = "") -> BroadcastEntry {
    BroadcastParser.csv("10000;\(time);\(days);CHL;TEST;S;SAm;sa;\(persistence);\(start);\(stop)").entries[0]
}

@Test func broadcastCSVRejectsMalformedAndDeduplicates() {
    let valid = "10000;0000-2400;;CHL;TEST;S;SAm;sa;1;;"
    let result = BroadcastParser.csv("kHz:75;Time(UTC):93;Days:59\n\(valid)\n\(valid)\nNaN;0000-2400;;CHL;BAD;S;SAm;;1;;\n10000;2360-2400;;CHL;BAD;S;SAm;;1;;\n<html>error</html>")
    #expect(result.entries.count == 1)
    #expect(result.skipped == 3)
    #expect(result.entries.first?.frequencyKHz == 10000)
    #expect(BroadcastParser.text(Data([0x43,0xe9])) == "Cé")
}

@Test(arguments: [
    ("2026-03-28T23:59:00Z","b25"),("2026-03-29T00:00:00Z","a26"),
    ("2026-10-24T23:59:00Z","a26"),("2026-10-25T00:00:00Z","b26"),
    ("2027-01-01T00:00:00Z","b26")
]) func broadcastSeasonBoundaries(test: (String,String)) {
    #expect(BroadcastCalendar.season(at: dateUTC(test.0)) == test.1)
}

@Test(arguments: [
    ("2300-0100","1","2026-10-13T00:30:00Z",BroadcastActivity.scheduled),
    ("2300-0100","2","2026-10-13T00:30:00Z",BroadcastActivity.off),
    ("2300-0100","1","2026-10-13T01:00:00Z",BroadcastActivity.off),
    ("0000-2400","1245","2026-10-13T12:00:00Z",BroadcastActivity.scheduled),
    ("0000-2400","1245","2026-10-14T12:00:00Z",BroadcastActivity.off),
    ("0000-2400","Fr-Mo","2026-10-12T12:00:00Z",BroadcastActivity.scheduled),
    ("0000-2400","Fr-Mo","2026-10-13T12:00:00Z",BroadcastActivity.off),
    ("0000-2400","irr","2026-10-13T12:00:00Z",BroadcastActivity.uncertain),
    ("0000-2400","1.Sa","2026-10-03T12:00:00Z",BroadcastActivity.scheduled),
    ("0000-2400","1.Sa","2026-10-10T12:00:00Z",BroadcastActivity.off),
    ("0000-2400","Last7","2026-10-25T12:00:00Z",BroadcastActivity.scheduled),
    ("0000-2400","MF-15","2026-10-16T12:00:00Z",BroadcastActivity.off),
    ("0000-2400","24Oct","2026-10-24T12:00:00Z",BroadcastActivity.scheduled)
]) func broadcastUTCDays(test: (String,String,String,BroadcastActivity)) {
    #expect(BroadcastCalendar.activity(entry(time: test.0, days: test.1), at: dateUTC(test.2), season: "a26") == test.3)
}

@Test func broadcastPartialSeasonAndInactive() {
    #expect(BroadcastCalendar.activity(entry(persistence: 6, start: "0110", stop: "2410"), at: dateUTC("2026-10-25T00:00:00Z"), season: "a26") == .off)
    #expect(BroadcastCalendar.activity(entry(persistence: 6, start: "2903", stop: "3006[0725]"), at: dateUTC("2026-10-13T00:00:00Z"), season: "a26") == .off)
    #expect(BroadcastCalendar.activity(entry(persistence: 96, start: "0112", stop: "3101"), at: dateUTC("2027-01-10T00:00:00Z"), season: "b26") == .scheduled)
    #expect(BroadcastCalendar.activity(entry(persistence: 98), at: dateUTC("2026-10-13T00:00:00Z"), season: "a26") == .inactive)
}

@Test func broadcastFavoriteAlertFindsNextConfidentUTCStart() {
    let weekday = entry(time: "0100-0200", days: "Mo-Fr")
    let next = BroadcastCalendar.nextScheduledStart(weekday, after: dateUTC("2026-10-11T23:00:00Z"))
    #expect(next == dateUTC("2026-10-12T01:00:00Z"))
    let after = BroadcastCalendar.nextScheduledStart(weekday, after: dateUTC("2026-10-12T01:05:00Z"))
    #expect(after == dateUTC("2026-10-13T01:00:00Z"))
    #expect(BroadcastCalendar.nextScheduledStart(entry(time: "0100-0200", days: "irr"), after: dateUTC("2026-10-11T23:00:00Z")) == nil)
}

@Test func broadcastReferenceSitesAndGeography() {
    let text = """
       I) Language codes.
       S     Spanish
       II) Country codes.
       CHL  Chile
       G    United Kingdom
       III) Target-area codes.
       SAm - South America
       IV) Transmitter site codes.
       CHL: sa-Santiago 33S27'00"-70W40'00"
       G: w-Woofferton 52N18-02W43
    """
    let reference = BroadcastReference.parse(text)
    #expect(reference.countries["CHL"] == "Chile")
    #expect(reference.languages["S"] == "Spanish")
    #expect(reference.targetName("SAm") == "South America")
    #expect(reference.targetName("SAs") == "South Asia")
    #expect(reference.targetName("UNKNOWN") == "UNKNOWN")
    let site = reference.site(for: entry())
    #expect(site != nil)
    #expect(abs((site?.latitude ?? 0) + 33.45) < 0.0001)
    let (km, _) = site!.distanceAndBearing(latitude: -33.45, longitude: -70.6666667)
    #expect(km < 0.001)
    let relayed = BroadcastParser.csv("10000;0000-2400;;CHL;TEST;S;SAm;/G-w;1;;").entries[0]
    #expect(reference.site(for: relayed)?.name == "Woofferton")
}
