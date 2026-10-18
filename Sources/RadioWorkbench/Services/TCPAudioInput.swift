import Foundation
import Network
import RadioCore

struct TCPAudioStream: Sendable {
    let ring: AudioSampleRing
    let sampleRate: Double
    /// Number of source channels. The ring contains the selected/downmixed mono.
    let channels: Int
}

struct TCPAudioSnapshot: Sendable {
    var bytesReceived: UInt64 = 0
    var framesDecoded: UInt64 = 0
    var clippedSamples: UInt64 = 0
    var droppedSamples: UInt64 = 0
    var connected = false
    var status = "Sin conexión TCP"
}

@MainActor
final class TCPAudioInput {
    private var active: TCPPCMConnection?
    private var generation = UUID()
    private let connectTimeout: TimeInterval
    private let idleTimeout: TimeInterval
    var snapshot: TCPAudioSnapshot { active?.snapshot ?? .init() }

    init(connectTimeout: TimeInterval = 5, idleTimeout: TimeInterval = 10) {
        self.connectTimeout = connectTimeout.isFinite ? max(0.05, min(60, connectTimeout)) : 5
        self.idleTimeout = idleTimeout.isFinite ? max(0.05, min(300, idleTimeout)) : 10
    }

    func start(configuration: NetworkPCMConfiguration, channel: AudioChannelSelection = .mix,
               onEnd: @escaping @MainActor @Sendable (String) -> Void) async throws -> TCPAudioStream {
        stop()
        _ = try configuration.validated(); try channel.validate(channelCount: configuration.channels)
        let token = UUID(); generation = token
        let ring = try AudioSampleRing()
        let transport = try TCPPCMConnection(configuration: configuration, channel: channel, ring: ring,
            connectTimeout: connectTimeout, idleTimeout: idleTimeout) { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    onEnd(message)
                }
            }
        active = transport
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in transport.start(continuation) }
            } onCancel: { transport.stop() }
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            return TCPAudioStream(ring: ring, sampleRate: configuration.sampleRate, channels: configuration.channels)
        } catch {
            if generation == token { transport.stop() }
            throw error
        }
    }

    func stop() {
        generation = UUID()
        active?.stop()
    }
}

/// Every connection/parser mutation runs on one dedicated serial queue.
/// The small statistics value alone crosses that queue under a lock. This is
/// the sole producer of its ring; the decoder remains the sole consumer.
private final class TCPPCMConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "RadioWorkbench.TCPAudio", qos: .userInitiated)
    private let connection: NWConnection
    private let ring: AudioSampleRing
    private let onEnd: @Sendable (String) -> Void
    private let connectTimeout: TimeInterval, idleTimeout: TimeInterval
    private let statsLock = NSLock()
    private var stats = TCPAudioSnapshot()
    private var parser: NetworkPCMParser
    private var continuation: CheckedContinuation<Void, any Error>?
    private var timer: DispatchSourceTimer?
    private var opened = false, terminal = false
    var snapshot: TCPAudioSnapshot {
        statsLock.withLock {
            var value = stats; value.droppedSamples = ring.dropped
            return value
        }
    }

    init(configuration: NetworkPCMConfiguration, channel: AudioChannelSelection, ring: AudioSampleRing,
         connectTimeout: TimeInterval, idleTimeout: TimeInterval, onEnd: @escaping @Sendable (String) -> Void) throws {
        parser = try NetworkPCMParser(configuration: configuration, channel: channel)
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else { throw NetworkPCMError.invalidConfiguration }
        connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: .tcp)
        self.ring = ring; self.connectTimeout = connectTimeout; self.idleTimeout = idleTimeout; self.onEnd = onEnd
    }

    func start(_ continuation: CheckedContinuation<Void, any Error>) {
        queue.async { [self] in
            guard !terminal else { continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            statsLock.withLock { stats.status = "Conectando con el audio local…" }
            connection.stateUpdateHandler = { [weak self] state in self?.stateChanged(state) }
            armTimeout(seconds: connectTimeout, message: "El emisor TCP local no respondió a tiempo. Revisa Network Sink y su puerto.")
            connection.start(queue: queue)
        }
    }
    func stop() {
        queue.async { [self] in finish(message: "Audio TCP detenido", error: CancellationError(), notify: false) }
    }
    private func stateChanged(_ state: NWConnection.State) {
        guard !terminal else { return }
        switch state {
        case .ready:
            opened = true
            statsLock.withLock { stats.connected = true; stats.status = "Audio TCP conectado; esperando muestras" }
            continuation?.resume(); continuation = nil
            armTimeout(seconds: idleTimeout, message: "La conexión TCP dejó de entregar audio. Revisa el emisor y vuelve a conectar.")
            receive()
        case .failed(let error), .waiting(let error):
            finish(message: "No se pudo mantener la conexión de audio local: \(error.localizedDescription)", error: error)
        case .cancelled:
            finish(message: "La conexión de audio TCP terminó.", error: CancellationError())
        default: break
        }
    }
    private func receive() {
        guard !terminal else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: NetworkPCMParser.maximumChunkBytes) { [weak self] data, _, complete, error in
            guard let self, !self.terminal else { return }
            if let data, !data.isEmpty {
                do {
                    let mono = try self.parser.append(data)
                    if !mono.isEmpty { self.ring.writeMono(mono) }
                    self.statsLock.withLock {
                        self.stats.bytesReceived = self.parser.bytesReceived
                        self.stats.framesDecoded = self.parser.framesDecoded
                        self.stats.clippedSamples = self.parser.clippedSamples
                        self.stats.status = "Recibiendo audio TCP local"
                    }
                    self.armTimeout(seconds: self.idleTimeout, message: "La conexión TCP dejó de entregar audio. Revisa el emisor y vuelve a conectar.")
                } catch {
                    self.statsLock.withLock { self.stats.bytesReceived = self.parser.bytesReceived }
                    self.finish(message: error.localizedDescription, error: error); return
                }
            }
            if let error { self.finish(message: "Se interrumpió el audio TCP: \(error.localizedDescription)", error: error); return }
            if complete {
                do {
                    try self.parser.finish()
                    self.finish(message: "El emisor cerró el audio TCP después de \(self.parser.framesDecoded) muestras.")
                } catch { self.finish(message: error.localizedDescription, error: error) }
                return
            }
            self.receive()
        }
    }
    private func armTimeout(seconds: TimeInterval, message: String) {
        if timer == nil {
            let newTimer = DispatchSource.makeTimerSource(queue: queue)
            timer = newTimer; newTimer.resume()
        }
        timer?.setEventHandler { [weak self] in
            self?.finish(message: message, error: URLError(.timedOut))
        }
        timer?.schedule(deadline: .now() + seconds, leeway: .milliseconds(20))
    }
    private func finish(message: String, error: (any Error)? = nil, notify: Bool = true) {
        guard !terminal else { return }
        terminal = true
        timer?.cancel(); timer = nil
        connection.stateUpdateHandler = nil; connection.cancel()
        ring.finish() // Decoder drains all accepted PCM before flushing its engine.
        statsLock.withLock { stats.connected = false; stats.status = message }
        continuation?.resume(throwing: error ?? URLError(.networkConnectionLost)); continuation = nil
        if opened && notify { onEnd(message) }
    }
}
