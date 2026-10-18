import Foundation
import Darwin

public struct RigctlState: Sendable, Equatable {
    public let frequencyHz: Double
    public let mode: String
    public let bandwidthHz: Int
}
public struct RigctlRequest: Sendable {
    public let frequencyHz: Double
    public let modulation: RFModulation
    public let bandwidthHz: Int
    public init(frequencyHz: Double, modulation: RFModulation, bandwidthHz: Int) {
        self.frequencyHz = frequencyHz; self.modulation = modulation; self.bandwidthHz = bandwidthHz
    }
    public var mode: String {
        switch modulation { case .am: "AM"; case .fm: "FM"; case .usb: "USB"; case .lsb: "LSB"; case .cw: "CW"; case .iq: "" }
    }
    public func validated() throws {
        guard frequencyHz.isFinite, (1000...20_000_000_000).contains(frequencyHz), !mode.isEmpty,
              (50...1_000_000).contains(bandwidthHz) else { throw RigctlError.invalidInput }
    }
    public var frequencyCommand: String { "F \(Int64(frequencyHz.rounded()))\n" }
    public var modeCommand: String { "M \(mode) \(bandwidthHz)\n" }
}
public enum RigctlError: LocalizedError {
    case invalidInput, connection(String), invalidReply, rejected(String), mismatch(RigctlState)
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Revisa frecuencia, modo AM/FM/USB/LSB/CW, ancho y puerto de Rigctl local."
        case .connection(let message): "No se pudo completar Rigctl: \(message). Habilita el servidor y elige el VFO en SDR++."
        case .invalidReply: "Rigctl devolvió una respuesta no válida o demasiado larga. No se confirmó la sintonía."
        case .rejected(let reply): "El servidor rechazó la orden: \(reply). El SDR puede conservar parte de los ajustes anteriores."
        case .mismatch(let state): "La lectura no confirma lo solicitado: \(state.frequencyHz) Hz · \(state.mode) · \(state.bandwidthHz) Hz. Comprueba VFO, permiso de sintonía y anchos admitidos en SDR++."
        }
    }
}

private final class RigctlSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var cancelled = false
    private var buffer = Data()
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if descriptor >= 0 { _ = shutdown(descriptor, SHUT_RDWR) }
    }
    func close() {
        lock.lock(); defer { lock.unlock() }
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }
    func connect(port: UInt16) throws {
        guard port > 0 else { throw RigctlError.invalidInput }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RigctlError.connection("socket") }
        lock.lock(); descriptor = fd; let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        var timeout = timeval(tv_sec: 3, tv_usec: 0), one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian
        _ = "127.0.0.1".withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard status == 0 else { throw RigctlError.connection(String(cString: strerror(errno))) }
        try checkCancellation()
    }
    private func checkCancellation() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
    }
    func send(_ command: String) throws {
        try checkCancellation()
        let bytes = Array(command.utf8)
        var offset = 0
        while offset < bytes.count {
            try checkCancellation()
            let sent = bytes.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress!.advanced(by: offset), bytes.count - offset, 0) }
            guard sent > 0 else { throw RigctlError.connection("no se pudo enviar la orden") }
            offset += sent
        }
    }
    func line() throws -> String {
        while true {
            try checkCancellation()
            if let end = buffer.firstIndex(of: 10) {
                let data = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                guard let text = String(data: data, encoding: .utf8) else { throw RigctlError.invalidReply }
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("RPRT ") && value != "RPRT 0" { throw RigctlError.rejected(value) }
                return value
            }
            guard buffer.count <= 4096 else { throw RigctlError.invalidReply }
            var bytes = [UInt8](repeating: 0, count: 1024)
            let count = recv(descriptor, &bytes, bytes.count, 0)
            guard count > 0 else { throw RigctlError.connection("conexión cerrada o tiempo de espera agotado") }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
    func query() throws -> RigctlState {
        try send("f\n")
        guard let frequency = Double(try line()), frequency.isFinite, (1...100_000_000_000).contains(frequency) else { throw RigctlError.invalidReply }
        try send("m\n")
        let mode = try line()
        guard mode.utf8.count <= 30, let bandwidth = Int(try line()), (0...10_000_000).contains(bandwidth) else { throw RigctlError.invalidReply }
        return .init(frequencyHz: frequency, mode: mode, bandwidthHz: bandwidth)
    }
}
public enum RigctlClient {
    public static func perform(port: UInt16 = 4532, request: RigctlRequest? = nil) async throws -> RigctlState {
        try request?.validated()
        let connection = RigctlSocket()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                defer { connection.close() }
                try Task.checkCancellation()
                try connection.connect(port: port)
                _ = try connection.query()
                if let request {
                    try connection.send(request.modeCommand)
                    guard try connection.line() == "RPRT 0" else { throw RigctlError.invalidReply }
                    try connection.send(request.frequencyCommand)
                    guard try connection.line() == "RPRT 0" else { throw RigctlError.invalidReply }
                }
                let result = try connection.query()
                if let request, abs(result.frequencyHz - request.frequencyHz.rounded()) > 1 || result.mode.uppercased() != request.mode || abs(result.bandwidthHz - request.bandwidthHz) > 1 {
                    throw RigctlError.mismatch(result)
                }
                return result
            }.value
        } onCancel: { connection.cancel() }
    }
}
