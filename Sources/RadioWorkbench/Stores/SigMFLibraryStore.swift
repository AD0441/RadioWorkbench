import AppKit
import Observation
import RadioCore

@MainActor @Observable final class SigMFLibraryStore {
    var entries: [SigMFLibraryEntry] = []
    var selectedID: UUID?
    var selectedRecording: SigMFRecording?
    var showsTrash = false
    var busy = false
    var status = "Importa el par .sigmf-meta / .sigmf-data para conservar sus parámetros I/Q."
    var error: String?
    @ObservationIgnored private let repository: SigMFLibrary
    @ObservationIgnored private var operation: Task<Void, Never>?
    init(repository: SigMFLibrary = .init()) { self.repository = repository }
    var visible: [SigMFLibraryEntry] { entries.filter { $0.trashed == showsTrash }.sorted { $0.importedAt > $1.importedAt } }
    var selected: SigMFLibraryEntry? { visible.first { $0.id == selectedID } }
    func load() { perform { self.entries = try await self.repository.load() } }
    func chooseImport() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.message = "Selecciona .sigmf-meta; las muestras deben estar junto a él. No se interpreta audio como I/Q."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let entry = try await self.repository.importRecording(metadata: url)
            self.entries = try await self.repository.load(); self.showsTrash = false; self.select(entry.id)
            self.status = "Importado y verificado SHA-512: \(entry.name)."
        }
    }
    func select(_ id: UUID?) {
        selectedID = id; selectedRecording = nil
        guard let id, entries.contains(where: { $0.id == id && !$0.trashed }) else { return }
        Task {
            do { let value = try await repository.recording(id: id); if selectedID == id { selectedRecording = value } }
            catch { if selectedID == id { self.error = error.localizedDescription } }
        }
    }
    func exportSelected() {
        guard let id = selected?.id else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Se creará una carpeta nueva con las muestras y sus metadatos SigMF."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        perform {
            let folder = try await self.repository.exportRecording(id: id, to: parent)
            self.status = "Par SigMF exportado y verificado."
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }
    func changeTrash() {
        guard let entry = selected else { return }
        perform {
            try await self.repository.setTrashed(id: entry.id, trashed: !entry.trashed)
            self.entries = try await self.repository.load(); self.select(nil)
        }
    }
    func cancel() { operation?.cancel() }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        operation = Task {
            defer { busy = false; operation = nil }
            do { try await action() }
            catch is CancellationError { status = "Operación cancelada; se conservan las grabaciones anteriores." }
            catch { self.error = error.localizedDescription }
        }
    }
}
