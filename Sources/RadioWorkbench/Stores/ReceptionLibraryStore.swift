import Foundation
import Observation
import RadioCore

@MainActor @Observable
final class ReceptionLibraryStore {
    var sessions: [ReceptionSession] = []
    var observations: [ListeningObservation] = []
    var category = "Todas"
    var selectedObservationID: UUID?
    var editingObservation: ListeningObservation?
    var selectedID: UUID?
    var search = ""
    var showsTrash = false
    var busy = false
    var error: String?
    var status = "Importa un audio o guarda el archivo que estás decodificando junto con sus ajustes."
    @ObservationIgnored private let repository: ReceptionLibraryRepository
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var activated = false

    init(repository: ReceptionLibraryRepository = .init()) { self.repository = repository }
    var selectedSession: ReceptionSession? { visibleSessions.first { $0.id == selectedID } }
    var visibleSessions: [ReceptionSession] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            category != "Escuchas anotadas" &&
            session.isTrashed == showsTrash && (query.isEmpty ||
                "\(session.title) \(session.mode.title) \(session.audio.originalFileName) \(session.rf.sourceDescription ?? "")"
                    .localizedCaseInsensitiveContains(query))
        }
    }
    var visibleObservations: [ListeningObservation] {
        guard category != "Con audio" else { return [] }
        return observations.filter {
            $0.isTrashed == showsTrash && (search.isEmpty || "\($0.stationName) \($0.notes) \($0.receivingStation.antenna)".localizedCaseInsensitiveContains(search))
        }
    }
    var activeCount: Int { sessions.filter { !$0.isTrashed }.count + observations.filter { !$0.isTrashed }.count }
    var trashCount: Int { sessions.filter(\.isTrashed).count + observations.filter(\.isTrashed).count }

    func load(force: Bool = false) {
        guard force || !activated else { return }
        activated = true
        perform {
            self.sessions = try await self.repository.load()
            self.observations = try await self.repository.loadObservations()
            self.status = "\(self.activeCount) recepciones guardadas · \(self.trashCount) en la papelera."
        }
    }
    func importAudio(from url: URL, title: String, mode: RadioMode, settings: DecoderSettings,
                     rf: ReceptionRFMetadata, capturedAt: Date?) {
        perform {
            let item = try await self.repository.importAudio(from: url, title: title, mode: mode,
                settings: settings, rf: rf, capturedAt: capturedAt)
            self.sessions = try await self.repository.load()
            self.observations = try await self.repository.loadObservations()
            self.showsTrash = false; self.search = ""; self.selectedID = item.id
            self.status = "Guardado: \(item.title). Se conservó una copia del audio original y sus ajustes."
        }
    }
    func saveObservation(_ observation: ListeningObservation) {
        perform {
            try await self.repository.saveObservation(observation)
            self.observations = try await self.repository.loadObservations()
            self.showsTrash = false; self.search = ""; self.category = "Todas"
            self.selectedObservationID = observation.id; self.selectedID = observation.id
            self.editingObservation = nil
            self.status = "Escucha guardada: \(observation.stationName). El mapa usa la posición y antena registradas en esa fecha."
        }
    }
    func trashObservation(_ item: ListeningObservation) {
        perform {
            try await self.repository.trashObservation(id: item.id, restore: item.isTrashed)
            self.observations = try await self.repository.loadObservations()
        }
    }
    func openSelected(onOpen: @escaping @MainActor (ReceptionSession, URL) -> Void) {
        guard let session = selectedSession else { return }
        perform {
            let url = try await self.repository.audioURL(for: session.id)
            self.status = "Abriendo \(session.title) con sus ajustes guardados…"
            onOpen(session, url)
        }
    }
    func trashSelected() {
        guard let session = selectedSession, !session.isTrashed else { return }
        perform {
            try await self.repository.trash(id: session.id)
            self.sessions = try await self.repository.load()
            self.observations = try await self.repository.loadObservations(); self.selectedID = nil
            self.status = "Recepción movida a la papelera. El audio se conserva y puedes restaurarlo."
        }
    }
    func restoreSelected() {
        guard let session = selectedSession, session.isTrashed else { return }
        perform {
            try await self.repository.restore(id: session.id)
            self.sessions = try await self.repository.load()
            self.observations = try await self.repository.loadObservations(); self.showsTrash = false
            self.selectedID = session.id; self.status = "Recepción restaurada."
        }
    }
    func cancel() { operation?.cancel() }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil
        operation = Task {
            defer { busy = false; operation = nil }
            do { try await action() }
            catch is CancellationError { status = "Operación cancelada. Las recepciones guardadas se conservan." }
            catch { self.error = error.localizedDescription }
        }
    }
}
