import Foundation
import Network
import Testing
@testable import RadioCore

private final class TestRigctlServer: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "RadioWorkbench.RigctlFixture")
    var peer: NWConnection?
    var frequency = 7100000.0, mode = "USB", bandwidth = 2400
    var buffer = "", commands: [String] = []
    var continuation: CheckedContinuation<UInt16, any Error>?
    let delay: Double
    let acceptsChanges: Bool
    init(acceptsChanges: Bool = true, delay: Double = 0) throws {
        self.delay = delay
        self.acceptsChanges = acceptsChanges
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                listener.stateUpdateHandler = { [self] state in
                    if case .ready = state, let port = listener.port { self.continuation?.resume(returning: port.rawValue); self.continuation = nil }
                    if case .failed(let error) = state { self.continuation?.resume(throwing: error); self.continuation = nil }
                }
                listener.newConnectionHandler = { [self] connection in peer = connection; connection.start(queue: queue); receive(connection) }
                listener.start(queue: queue)
            }
        }
    }
    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, complete, error in
            if let data {
                buffer += String(decoding: data, as: UTF8.self)
                while let end = buffer.firstIndex(of: "\n") {
                    let command = String(buffer[..<end]); buffer.removeSubrange(...end); commands.append(command)
                    let parts = command.split(separator: " ")
                    let answer: String
                    if command == "f" { answer = "\(frequency)\n" }
                    else if command == "m" { answer = "\(mode)\n\(bandwidth)\n" }
                    else if parts.first == "F", parts.count == 2 {
                        if acceptsChanges { frequency = Double(parts[1])! }; answer = "RPRT 0\n"
                    } else if parts.first == "M", parts.count == 3 {
                        if acceptsChanges { mode = String(parts[1]); bandwidth = Int(parts[2])! }; answer = "RPRT 0\n"
                    } else { answer = "RPRT -1\n" }
                    queue.asyncAfter(deadline: .now() + delay) { connection.send(content: Data(answer.utf8), completion: .contentProcessed { _ in }) }
                }
            }
            if !complete && error == nil { receive(connection) }
        }
    }
    func recordedCommands() async -> [String] { await withCheckedContinuation { c in queue.async { [self] in c.resume(returning: commands) } } }
    func stop() { queue.async { [self] in peer?.cancel(); listener.cancel() } }
}
@Test func rigctlAppliesWhitelistedSettingsAndConfirmsReadback() async throws {
    let server = try TestRigctlServer(); defer { server.stop() }
    let port = try await server.start()
    let request = RigctlRequest(frequencyHz: 145500000, modulation: .fm, bandwidthHz: 12500)
    let result = try await RigctlClient.perform(port: port, request: request)
    #expect(result.frequencyHz == 145500000 && result.mode == "FM" && result.bandwidthHz == 12500)
    #expect(await server.recordedCommands() == ["f", "m", "M FM 12500", "F 145500000", "f", "m"])
}
@Test func rigctlDoesNotTrustSuccessWhenTuningIsDisabled() async throws {
    let server = try TestRigctlServer(acceptsChanges: false); defer { server.stop() }
    let port = try await server.start()
    await #expect(throws: RigctlError.self) { try await RigctlClient.perform(port: port, request: .init(frequencyHz: 10000000, modulation: .am, bandwidthHz: 9000)) }
    #expect(throws: RigctlError.self) { try RigctlRequest(frequencyHz: .nan, modulation: .am, bandwidthHz: 9000).validated() }
    #expect(throws: RigctlError.self) { try RigctlRequest(frequencyHz: 1000000, modulation: .iq, bandwidthHz: 9000).validated() }
}

@Test func rigctlCancellationStopsBeforeAnyTuningCommand() async throws {
    let server = try TestRigctlServer(delay: 0.5); defer { server.stop() }
    let port = try await server.start()
    let operation = Task { try await RigctlClient.perform(port: port, request: .init(frequencyHz: 145500000, modulation: .fm, bandwidthHz: 12500)) }
    try await Task.sleep(for: .milliseconds(50)); operation.cancel()
    do { _ = try await operation.value; Issue.record("Cancelled operation unexpectedly completed") } catch { }
    let commands = await server.recordedCommands()
    #expect(!commands.contains { $0.hasPrefix("F ") || $0.hasPrefix("M ") })
}
