import Foundation
import Network
import Testing
@testable import RadioCore
@testable import RadioWorkbench

private final class LoopbackPCMServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "RadioWorkbench.Tests.LocalPCM")
    private let listener: NWListener
    private let chunks: [Data]
    private let closes: Bool
    private var peer: NWConnection?
    private var continuation: CheckedContinuation<UInt16, any Error>?
    init(chunks: [Data], closes: Bool = true) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.chunks = chunks; self.closes = closes
    }
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    if case .ready = state, let port = self.listener.port {
                        self.continuation?.resume(returning: port.rawValue); self.continuation = nil
                    } else if case .failed(let error) = state {
                        self.continuation?.resume(throwing: error); self.continuation = nil
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    self.peer = connection
                    connection.stateUpdateHandler = { [weak self] state in
                        if case .ready = state { self?.send(index: 0) }
                    }
                    connection.start(queue: self.queue)
                }
                listener.start(queue: queue)
            }
        }
    }
    private func send(index: Int) {
        guard let peer else { return }
        guard index < chunks.count else {
            if closes {
                peer.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
            }
            return
        }
        peer.send(content: chunks[index], completion: .contentProcessed { [weak self] error in
            if error == nil { self?.send(index: index + 1) }
        })
    }
    func stop() { queue.async { [self] in peer?.cancel(); listener.cancel() } }
}
@MainActor private final class TCPEndNotice { var message: String? }
@MainActor private func awaitTCPFinish(_ stream: TCPAudioStream, notice: TCPEndNotice) async throws {
    let limit = Date().addingTimeInterval(5)
    while (!stream.ring.isFinished || notice.message == nil) && Date() < limit {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(stream.ring.isFinished)
    #expect(notice.message != nil)
}

@Test @MainActor func tcpAudioInputReceivesFragmentedLocalPCMAndFinishesWithoutMicrophone() async throws {
    let bytes = Data([0, 128, 0, 64, 255, 127, 0, 0]) // -1, +0.5, max, zero
    let server = try LoopbackPCMServer(chunks: [bytes.prefix(1), bytes.dropFirst(1).prefix(2), bytes.dropFirst(3)])
    defer { server.stop() }
    let port = try await server.start(), input = TCPAudioInput(), notice = TCPEndNotice()
    defer { input.stop() }
    let stream = try await input.start(configuration: .init(port: port), onEnd: { notice.message = $0 })
    try await awaitTCPFinish(stream, notice: notice)
    var buffer = [Float](repeating: 0, count: 16)
    let count = stream.ring.read(into: &buffer)
    #expect(Array(buffer.prefix(count)) == [-1, 0.5, Float(32767) / 32768, 0])
    #expect(stream.sampleRate == 48000 && stream.channels == 1)
    #expect(input.snapshot.bytesReceived == 8 && input.snapshot.framesDecoded == 4)
    #expect(input.snapshot.droppedSamples == 0 && !input.snapshot.connected)
}

@Test @MainActor func tcpAudioInputReportsTruncationAndIdleTimeout() async throws {
    let truncated = try LoopbackPCMServer(chunks: [Data([0, 0, 0])])
    defer { truncated.stop() }
    let firstPort = try await truncated.start(), input = TCPAudioInput(idleTimeout: 0.15), notice = TCPEndNotice()
    defer { input.stop() }
    let first = try await input.start(configuration: .init(port: firstPort, channels: 2), onEnd: { notice.message = $0 })
    try await awaitTCPFinish(first, notice: notice)
    #expect(notice.message?.contains("mitad") == true)
    #expect(input.snapshot.framesDecoded == 0)
    let idle = try LoopbackPCMServer(chunks: [], closes: false); defer { idle.stop() }
    let secondPort = try await idle.start(), secondNotice = TCPEndNotice()
    let second = try await input.start(configuration: .init(port: secondPort), onEnd: { secondNotice.message = $0 })
    try await awaitTCPFinish(second, notice: secondNotice)
    #expect(secondNotice.message?.contains("entregar audio") == true)
    #expect(input.snapshot.bytesReceived == 0)
}

@Test @MainActor func tcpAudioInputBoundsRingAndRejectsRemoteHost() async throws {
    let input = TCPAudioInput()
    defer { input.stop() }
    await #expect(throws: NetworkPCMError.self) {
        try await input.start(configuration: .init(host: "192.168.1.2"), onEnd: { _ in })
    }
    let payload = Data(repeating: 0, count: 400_000)
    let chunks = stride(from: 0, to: payload.count, by: 4096).map { payload.subdata(in: $0..<min($0 + 4096, payload.count)) }
    let server = try LoopbackPCMServer(chunks: chunks); defer { server.stop() }
    let port = try await server.start(), notice = TCPEndNotice()
    let stream = try await input.start(configuration: .init(port: port), onEnd: { notice.message = $0 })
    try await awaitTCPFinish(stream, notice: notice)
    #expect(input.snapshot.framesDecoded == 200_000)
    #expect(input.snapshot.droppedSamples > 0)
    #expect(stream.ring.written + stream.ring.dropped == 200_000)
}

@Test @MainActor func tcpAudioInputManualStopDoesNotReportAnOldConnectionAsCurrent() async throws {
    let server = try LoopbackPCMServer(chunks: [], closes: false); defer { server.stop() }
    let port = try await server.start(), input = TCPAudioInput(idleTimeout: 0.1), notice = TCPEndNotice()
    let stream = try await input.start(configuration: .init(port: port), onEnd: { notice.message = $0 })
    input.stop()
    try await Task.sleep(for: .milliseconds(200))
    #expect(stream.ring.isFinished && notice.message == nil)
}
