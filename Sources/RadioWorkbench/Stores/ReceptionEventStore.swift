import AppKit
import CryptoKit
import Observation
import RadioCore

@MainActor @Observable final class ReceptionEventStore {
    var events: [ReceptionEvent] = []
    var selectedID: String?
    var sourceFilter = "Todas"
    var status = "Las posiciones aparecen al recibir mensajes con coordenadas."
    var error: String?
    var busy = false
    var importedAt: Date?
    private var seen: Set<String> = []
    var visible: [ReceptionEvent] { events.filter { sourceFilter == "Todas" || $0.source == sourceFilter } }
    var sources: [String] { Array(Set(events.map(\.source))).sorted() }
    var latestPositions: [ReceptionEvent] {
        var tracks: Set<String> = []
        return visible.filter { $0.location != nil && tracks.insert($0.trackID).inserted }
    }
    func ingest(_ event: ReceptionEvent) {
        guard (try? event.validated()) != nil, seen.insert(event.id).inserted else { return }
        events.append(event); events.sort { $0.receivedAt > $1.receivedAt }
        if events.count > 5000 { events.removeLast(events.count - 5000); seen = Set(events.map(\.id)) }
    }
    func ingestAPRS(_ position: RadioPosition) {
        ingest(ReceptionEvent(id: "aprs-is|\(position.id)|\(position.receivedAt.timeIntervalSince1970)", source: "APRS-IS",
            sourceKind: .internet, protocolName: "APRS", entityID: position.id, receivedAt: position.receivedAt,
            latitude: position.latitude, longitude: position.longitude,
            message: position.comment + " · " + position.path, integrity: "Reporte de Internet; no confirma recepción RF local."))
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let (document, digest) = try await Task.detached(priority: .utility) {
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let data = try handle.read(upToCount: 10_000_001) ?? Data()
                    let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
                    return (try ReceptionEventDocument.decode(data), digest)
                }.value
                for event in document.events {
                    // External IDs cannot replace events produced inside the app.
                    ingest(ReceptionEvent(id: "import|\(digest)|" + SHA256.hash(data: Data(event.id.utf8)).map { String(format: "%02x", $0) }.joined(),
                        source: event.source, sourceKind: .imported,
                        protocolName: event.protocolName, entityID: event.entityID, receivedAt: event.receivedAt,
                        observedAt: event.observedAt, importedAt: Date(), latitude: event.latitude, longitude: event.longitude,
                        message: event.message, integrity: event.integrity))
                }
                importedAt = Date(); status = "\(document.events.count) eventos válidos leídos. Las afirmaciones del adaptador conservan su procedencia; no se verificó su CRC aquí."
            } catch { self.error = error.localizedDescription }
        }
    }
    func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "recepciones-events-v1.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ReceptionEventDocument(events: visible).encoded().write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}
