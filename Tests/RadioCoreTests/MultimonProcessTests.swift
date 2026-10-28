import Foundation
import Testing
@testable import RadioCore

private func temporaryMultimonScript(_ source: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("multimon-process-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("helper")
    try Data(("#!/bin/sh\n" + source + "\n").utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@Test func multimonCancellationEscalatesOnlyTheOwnedHelperIfSIGTERMIgnored() async throws {
    // exec keeps exactly one owned PID; tail inherits SIGTERM ignored and does
    // not create a CPU busy loop or any descendants that could outlive the test.
    let script = try temporaryMultimonScript("trap '' TERM\nprintf 'ready\\n' >&2\nexec /usr/bin/tail -f /dev/null")
    defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
    let helper = try MultimonProcess(mode: .pocsag, settings: DecoderSettings(), executableURL: script)
    defer { helper.cancel() }
    let readyBy = Date().addingTimeInterval(3)
    while !helper.snapshot.diagnostics.contains("ready") && Date() < readyBy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(helper.snapshot.diagnostics.contains("ready"))
    helper.cancel()
    helper.cancel() // idempotent; no process-group/name signals
    let stopBy = Date().addingTimeInterval(3)
    while helper.isRunning && Date() < stopBy { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!helper.isRunning)
}

@Test func multimonRejectsOneOversizeLineThenRecoversAndDrainsFinalEOFLine() throws {
    let event = #"{"demod_name":"POCSAG1200","address":123456,"function":3,"alpha":"CQ RWB"}"#
    let script = try temporaryMultimonScript("/usr/bin/printf '%s\\n' '\(String(repeating: "x", count: 70_000))'\n/usr/bin/printf '%s\\n' '\(event)'\n/usr/bin/printf '%s' '\(event)'\n/bin/cat >/dev/null")
    defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
    let helper = try MultimonProcess(mode: .pocsag, settings: DecoderSettings(), executableURL: script)
    defer { helper.cancel() }
    let result = try helper.finish()
    #expect(result.invalidLines == 1)
    #expect(result.total == 2)
    #expect(result.records.map(\.address) == [123456, 123456])
}

@Test func multimonOldExportWithoutFLEXMetadataStillDecodes() throws {
    let legacy = #"{"id":"0EC16081-4D25-4C3E-8C66-B36E9580E1B4","decoder":"POCSAG1200","address":123456,"function":3,"kind":"ALPHA","body":"CQ RWB"}"#
    let record = try JSONDecoder().decode(MultimonRecord.self, from: Data(legacy.utf8))
    #expect(record.flex == nil)
    #expect(record.address == 123456)
}
