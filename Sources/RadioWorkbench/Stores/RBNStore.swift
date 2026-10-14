import Foundation
import Network
import Observation
import RadioCore

@MainActor @Observable final class RBNStore {
    var login = UserDefaults.standard.string(forKey: "rbnLogin") ?? ""
    var feed: RBNFeed = .cwRTTY
    var bandFilter = "Todas"
    var modeFilter = "Todos"
    var spots: [RBNSpot] = []
    var status = "Desconectado. La conexión a RBN es manual y solo recibe spots."
    var connected = false
    private var connection: NWConnection?
    private var decoder = RBNTelnetDecoder()
    private var sessionID = UUID()

    var visibleSpots: [RBNSpot] {
        spots.filter { spot in
            (bandFilter == "Todas" || spot.band == bandFilter)
                && (modeFilter == "Todos" || spot.mode == modeFilter || (modeFilter == "FT8" && spot.mode == "FT4"))
        }
    }

    func connect() {
        guard connection == nil else { return }
        guard let validLogin = RBNParser.validLogin(login) else {
            status = "Introduce un indicativo o alias válido (hasta 16 letras, números, / o -)."
            return
        }
        login = validLogin
        UserDefaults.standard.set(validLogin, forKey: "rbnLogin")
        decoder = RBNTelnetDecoder()
        let token = UUID()
        sessionID = token
        status = "Conectando a telnet.reversebeacon.net:\(feed.port)…"
        let endpointPort = NWEndpoint.Port(rawValue: feed.port)!
        let newConnection = NWConnection(host: "telnet.reversebeacon.net", port: endpointPort, using: .tcp)
        connection = newConnection
        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.handle(state, token: token) }
        }
        newConnection.start(queue: DispatchQueue.global(qos: .utility))
    }

    func disconnect() {
        sessionID = UUID()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        connected = false
        status = "Desconectado. Los spots recibidos se conservan hasta cerrar la app."
    }

    func clear() { spots.removeAll(keepingCapacity: true) }

    private func handle(_ state: NWConnection.State, token: UUID) {
        guard token == sessionID else { return }
        switch state {
        case .ready:
            connected = true
            status = "Conectado a RBN · puerto \(feed.port). Enviando el indicativo de acceso…"
            let login = self.login
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.sessionID == token, let connection = self.connection else { return }
                connection.send(content: Data((login + "\r\n").utf8), completion: .contentProcessed { [weak self] error in
                    if let error { Task { @MainActor [weak self] in self?.status = "No se pudo enviar el indicativo: \(error)" } }
                })
                self.status = "Recibiendo RBN · \(self.feed.rawValue). Filtro local: \(self.bandFilter), \(self.modeFilter)."
                self.receive(token: token)
            }
        case .failed(let error):
            connected = false
            status = "RBN desconectado: \(error.localizedDescription). Puedes reintentar manualmente."
            connection?.cancel(); connection = nil
        case .cancelled:
            connected = false
        default: break
        }
    }

    private func receive(token: UUID) {
        guard token == sessionID, let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == token else { return }
                if let data, !data.isEmpty {
                    let decoded = self.decoder.consume(data)
                    if !decoded.replies.isEmpty {
                        connection.send(content: Data(decoded.replies), completion: .contentProcessed { _ in })
                    }
                    for line in decoded.lines {
                        guard let spot = RBNParser.parse(line), spot.band != nil else { continue }
                        self.spots.insert(spot, at: 0)
                    }
                    if self.spots.count > 1_000 { self.spots.removeLast(self.spots.count - 1_000) }
                }
                if complete || error != nil {
                    self.connected = false
                    self.status = "La conexión RBN terminó. Se conservaron \(self.spots.count) spots; pulsa Conectar para reintentar."
                    self.connection?.cancel(); self.connection = nil
                } else { self.receive(token: token) }
            }
        }
    }
}
