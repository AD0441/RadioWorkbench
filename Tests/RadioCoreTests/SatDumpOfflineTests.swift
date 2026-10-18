import Foundation
import Testing
@testable import RadioCore

private func satDumpTestInput(_ folder: URL) throws -> SatDumpIQInput {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("capture with spaces.cf32")
    try Data(repeating: 0, count: 8000).write(to: file)
    return .init(file: file, sampleRate: 1_000_000, format: .cf32, centerFrequencyHz: 137_900_000,
                 capturedAt: Date(timeIntervalSince1970: 1_790_000_000), pipeline: .k72)
}
@Test func satDumpRejectsAudioHeadersAndPreservesExplicitIQParameters() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try satDumpTestInput(directory)
    #expect(try input.validated() == 8000)
    let args = input.arguments(output: directory.appendingPathComponent("output"), tle: directory.appendingPathComponent("empty.tle"))
    #expect(args[0] == "meteor_m2-x_lrpt" && args[1] == "baseband" && args[2] == input.file.path)
    #expect(args.contains("--tle_override") && !args.contains("live"))
    try Data("RIFF000000000000".utf8).write(to: input.file)
    #expect(throws: SatDumpOfflineError.self) { try input.validated() }
}
@Test func satDumpOfflineImportsProductsFromAnIsolatedMockCLI() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try satDumpTestInput(directory)
    let mock = directory.appendingPathComponent("satdump-fixture")
    let source = """
    #!/usr/bin/python3
    import sys,pathlib,json
    output=pathlib.Path(sys.argv[4])
    (output/'dataset.json').write_text(json.dumps({'satellite':'Synthetic fixture','products':[]}))
    (output/'channel.png').write_bytes(bytes.fromhex('89504e470d0a1a0a'))
    try:
        (output.parent.parent/'outside.txt').write_text('must be denied')
    except PermissionError:
        print('outside writes blocked',flush=True)
    print('Progress 37.5%',flush=True)
    """
    try source.write(to: mock, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mock.path)
    let result = try await SatDumpOfflineEngine.run(executable: mock, input: input, directory: directory.appendingPathComponent("job")) { _ in }
    #expect(result.exitCode == 0 && result.products.count == 2 && result.images.count == 1)
    #expect(result.log.contains("Progress 37.5%") && result.log.contains("outside writes blocked"))
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("outside.txt").path))
    #expect(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("iq-input.json").path))
}

private actor SatDumpStarted {
    var seen = false
    func mark() { seen = true }
}
@Test func satDumpOfflineCancellationTerminatesOnlyItsOwnJob() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try satDumpTestInput(directory), mock = directory.appendingPathComponent("satdump-wait")
    try "#!/usr/bin/python3\nimport time\ntime.sleep(30)\n".write(to: mock, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mock.path)
    let started = SatDumpStarted()
    let operation = Task { try await SatDumpOfflineEngine.run(executable: mock, input: input, directory: directory.appendingPathComponent("cancelled-job")) { _ in await started.mark() } }
    let deadline = Date().addingTimeInterval(5)
    while !(await started.seen) && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await started.seen)
    operation.cancel()
    await #expect(throws: CancellationError.self) { try await operation.value }
}
