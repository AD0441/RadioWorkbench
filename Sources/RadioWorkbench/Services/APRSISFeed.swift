import Foundation
import Network
import Observation
import RadioCore

@MainActor @Observable final class APRSISStore {
    private var storedCallsign = UserDefaults.standard.string(forKey: "aprsISCallsign") ?? ""
    var callsign: String {
        get { storedCallsign }
        set {
            let normalized = newValue.uppercased()
            storedCallsign = normalized
            UserDefaults.standard.set(normalized, forKey: "aprsISCallsign")
        }
    }
    var radiusKilometers = 50.0
    var positions: [RadioPosition] = []
    var selectedPositionID: String?
    var connected = false
    var status = "Conecta para consultar estaciones APRS cercanas por Internet."
    private let feed = APRSISFeed()

    func connect(location: RadioLocation?) {
        guard let location else { status = "Guarda una ubicación válida en Condiciones y propagación antes de consultar APRS."; return }
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard call.range(of: #"^[A-Z0-9]{3,6}(-[A-Z0-9]{1,2})?$"#, options: .regularExpression) != nil, !call.contains("NOCALL") else {
            status = "Escribe tu indicativo de radioaficionado para iniciar una sesión de solo recepción APRS-IS."; return
        }
        stop(); positions = []; connected = true
        status = "Conectando a APRS-IS con filtro de \(Int(radiusKilometers)) km…"
        feed.start(callsign: call, latitude: location.latitude, longitude: location.longitude, radius: radiusKilometers,
                   onStatus: { [weak self] value in
                       guard let self else { return }; self.status = value
                       if value.hasPrefix("APRS-IS no disponible") || value.hasPrefix("La conexión APRS-IS") || value.hasPrefix("El servidor APRS-IS") { self.connected = false }
                   },
                   onPosition: { [weak self] position in
                       guard let self else { return }
                       if let index = self.positions.firstIndex(where: { $0.id == position.id }) { self.positions[index] = position }
                       else { self.positions.insert(position, at: 0) }
                       self.positions.sort { $0.receivedAt > $1.receivedAt }
                       if self.positions.count > 200 { self.positions.removeLast(self.positions.count - 200) }
                       self.status = "APRS-IS · \(self.positions.count) estaciones/objetos únicos · solo recepción"
                   })
    }

    func stop() {
        feed.stop(); connected = false
        if status.hasPrefix("APRS-IS ·") || status.hasPrefix("Conectando") { status = "Conexión detenida. Los puntos recibidos se mantienen en esta sesión." }
    }
}

@MainActor private final class APRSISFeed {
    private var connection: NWConnection?
    private var buffer = ""
    private var loginSent = false
    private var onStatus: ((String) -> Void)?
    private var onPosition: ((RadioPosition) -> Void)?

    func start(callsign: String, latitude: Double, longitude: Double, radius: Double,
               onStatus: @escaping (String) -> Void, onPosition: @escaping (RadioPosition) -> Void) {
        stop(); buffer = ""; loginSent = false; self.onStatus = onStatus; self.onPosition = onPosition
        let nwConnection = NWConnection(host: "srvr.aprs-is.net", port: 14580, using: .tcp)
        connection = nwConnection
        nwConnection.stateUpdateHandler = { [weak self, weak nwConnection] state in
            Task { @MainActor in
                guard let self, let nwConnection else { return }
                switch state {
                case .ready:
                    self.onStatus?("Conectado al servidor APRS-IS; iniciando filtro geográfico en modo solo recepción…")
                    self.receive(from: nwConnection, callsign: callsign, latitude: latitude, longitude: longitude, radius: radius)
                case .failed(let error): self.onStatus?("APRS-IS no disponible: \(error.localizedDescription)"); self.stop()
                case .cancelled: break
                default: break
                }
            }
        }
        nwConnection.start(queue: .main)
    }

    func stop() {
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
    }

    private func receive(from connection: NWConnection, callsign: String, latitude: Double, longitude: Double, radius: Double) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, complete, error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                if let data, !data.isEmpty { self.consume(data, connection: connection, callsign: callsign, latitude: latitude, longitude: longitude, radius: radius) }
                if let error { self.onStatus?("La conexión APRS-IS terminó: \(error.localizedDescription)"); self.stop(); return }
                if complete { self.onStatus?("El servidor APRS-IS cerró la conexión."); self.stop(); return }
                self.receive(from: connection, callsign: callsign, latitude: latitude, longitude: longitude, radius: radius)
            }
        }
    }

    private func consume(_ data: Data, connection: NWConnection, callsign: String, latitude: Double, longitude: Double, radius: Double) {
        buffer += String(decoding: data, as: UTF8.self)
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""
        for raw in lines.dropLast() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if !loginSent {
                let lat = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), latitude)
                let lon = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), longitude)
                let login = "user \(callsign) pass -1 vers RadioWorkbench 0.9.0 filter r/\(lat)/\(lon)/\(Int(radius))\r\n"
                connection.send(content: login.data(using: .utf8), completion: .contentProcessed { [weak self] error in
                    if let error { Task { @MainActor in self?.onStatus?("No se pudo enviar el filtro APRS: \(error.localizedDescription)") } }
                })
                loginSent = true
                onStatus?("APRS-IS conectado · filtro circular de \(Int(radius)) km · passcode −1 (solo recepción).")
            }
            guard !line.hasPrefix("#") else { continue }
            if let position = APRSPositionParser.parse(line) { onPosition?(position) }
        }
    }
}
