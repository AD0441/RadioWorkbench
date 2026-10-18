import Foundation
import Testing
@testable import RadioCore

@Test func hfccArchiveFindsActualScheduleWithoutReadingReferenceTable() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("REFERENCE NOT SCHEDULE".utf8).write(to: folder.appendingPathComponent("site.txt"))
    try Data("SYNTHETIC SCHEDULE".utf8).write(to: folder.appendingPathComponent("A26all00.TXT"))
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = folder
    process.arguments = ["-q", "schedule.zip", "site.txt", "A26all00.TXT"]
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let archive = try Data(contentsOf: folder.appendingPathComponent("schedule.zip"))
    #expect(try HFCCScheduleService.scheduleText(from: archive, season: "a26") == "SYNTHETIC SCHEDULE")
    #expect(throws: (any Error).self) { try HFCCScheduleService.scheduleText(from: archive, season: "b26") }
}

@Test func hfccDaysUseSundayOneAndDoNotReuseEiBiMondayOne() {
    let tx = HFCCTransmission(frequencyKHz: 10000, startUTC: "1200", stopUTC: "1300", targetArea: "", siteCode: "ABC", powerKW: 10, azimuthDegrees: nil, days: "1", startDate: "290326", stopDate: "241026", modulationCode: "D", language: "Eng", broadcasterCode: "ABC", managerCode: "ABC", raw: "synthetic")
    let date = ISO8601DateFormatter()
    #expect(tx.operates(on: date.date(from: "2026-10-18T12:00:00Z")!))
    #expect(!tx.operates(on: date.date(from: "2026-10-19T12:00:00Z")!))
    #expect(!tx.operates(on: date.date(from: "2026-11-01T12:00:00Z")!))
}
