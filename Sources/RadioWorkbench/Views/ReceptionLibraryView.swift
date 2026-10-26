import AppKit
import SwiftUI
import RadioCore
import UniformTypeIdentifiers

struct ReceptionLibraryView: View {
    @Bindable var store: ReceptionLibraryStore
    let onRecord: () -> Void
    let currentAudioURL: URL?
    let mode: RadioMode
    let settings: DecoderSettings
    let rf: ReceptionRFMetadata
    let onPrepareIQ: (SigMFRecording) -> Void
    let onOpen: @MainActor (ReceptionSession, URL) -> Void
    @ViewState private var title = ""
    @ViewState private var frequencyMHz = ""
    @ViewState private var captureDateKnown = false
    @ViewState private var captureDate = Date()
    @ViewState private var showsIQ = false
    private let utc = TimeZone(secondsFromGMT: 0)!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Biblioteca", selection: $showsIQ) {
                Text("Audio y escuchas").tag(false)
                Text("I/Q · SigMF").tag(true)
            }.pickerStyle(.segmented).frame(width: 350).padding(.horizontal, 20).padding(.top, 16)
            if showsIQ { SigMFLibraryView(store: store.sigMF, onPrepare: onPrepareIQ) }
            else { audioLibrary }
        }
    }
    private var audioLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Biblioteca de recepciones").font(.largeTitle.weight(.semibold))
            Text("Escuchas anotadas y audio original con sus ajustes. Las anotaciones no necesitan grabación.").foregroundStyle(.secondary)
            Button("Anotar escucha sin audio…", systemImage: "square.and.pencil", action: onRecord).buttonStyle(.borderedProminent)
            GroupBox("Guardar audio y configuración") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Nombre opcional de la recepción", text: $title).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Nombre de la recepción")
                        Button("Importar audio…") { importAudio() }.disabled(store.busy)
                        Button("Guardar archivo actual") { if let currentAudioURL { save(currentAudioURL) } }
                            .disabled(currentAudioURL == nil || store.busy)
                    }
                    HStack {
                        Text("Ajustes: \(mode.title) · \(rf.modulation.rawValue) · \(rf.bandwidthHz.formatted()) Hz RF")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        TextField("RF en MHz, si se conoce", text: $frequencyMHz).textFieldStyle(.roundedBorder)
                            .frame(width: 200).accessibilityLabel("Frecuencia RF en MHz de la grabación")
                    }
                    HStack {
                        Toggle("Conozco la fecha de captura", isOn: $captureDateKnown)
                        if captureDateKnown {
                            DatePicker("Captura · UTC", selection: $captureDate).environment(\.timeZone, utc)
                                .datePickerStyle(.field)
                        }
                    }
                    Text("Se guarda una copia local del archivo, hasta 1 GB. La fecha de importación se registra aparte: si no conoces cuándo se grabó, la captura queda sin fecha. Las entradas en vivo deben guardarse primero como archivo de audio.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            HStack {
                Picker("Mostrar", selection: $store.category) {
                    ForEach(["Todas", "Escuchas anotadas", "Con audio"], id: \.self) { Text(AppLocalization.text($0)) }
                }.frame(width: 220)
                TextField("Buscar nombre, modo o archivo", text: $store.search).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Buscar en la biblioteca")
                Toggle("Papelera (\(store.trashCount))", isOn: $store.showsTrash).toggleStyle(.button)
                Button { store.load(force: true) } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                    .disabled(store.busy)
                if store.busy { ProgressView().controlSize(.small); Button("Cancelar") { store.cancel() } }
            }
            if let error = store.error { Text(AppLocalization.text(error)).foregroundStyle(.red).textSelection(.enabled) }
            Text(AppLocalization.text(store.status)).font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(selection: $store.selectedID) {
                    ForEach(store.visibleObservations) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(item.stationName, systemImage: item.outcome == .heard ? "ear" : "note.text").font(.headline)
                            Text("\(item.outcome.title) · \(item.frequencyHz / 1000, specifier: "%.2f") kHz · \(item.band)").font(.caption)
                            Text("\(utcText(item.observedAt)) · \(item.receivingStation.antenna)").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(item.id)
                    }
                    ForEach(store.visibleSessions) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(item.title, systemImage: item.sourceKind == .audio ? "waveform" : "waveform.path")
                                .font(.headline).lineLimit(2)
                            Text("\(item.mode.title) · \(item.audio.durationSeconds.formatted(.number.precision(.fractionLength(1)))) s")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Importado \(utcText(item.importedAt))").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(item.id)
                    }
                }.frame(minWidth: 250, idealWidth: 320)
                    .overlay { if store.visibleSessions.isEmpty && store.visibleObservations.isEmpty { Text(store.showsTrash ? "La papelera está vacía." : "Todavía no hay recepciones para mostrar.").foregroundStyle(.secondary).padding() } }
                ScrollView {
                    if let item = store.visibleObservations.first(where: { $0.id == store.selectedID }) { observationDetail(item).padding(16) }
                    else if let item = store.selectedSession { detail(item).padding(16) }
                    else { Text("Selecciona una recepción para ver su audio y sus ajustes.").foregroundStyle(.secondary).padding(24) }
                }.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(minHeight: 300)
        }.padding(20).task { store.load() }
    }

    private func observationDetail(_ item: ListeningObservation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.stationName).font(.title2.weight(.semibold))
            LabeledContent("Resultado", value: AppLocalization.text(item.outcome.title))
            LabeledContent("Frecuencia", value: "\((item.frequencyHz / 1000).formatted()) kHz · \(item.modulation)")
            LabeledContent("Observación UTC", value: utcText(item.observedAt))
            if let end = item.endedAt { LabeledContent("Fin UTC", value: utcText(end)) }
            LabeledContent("Origen", value: AppLocalization.text(item.receivingStation.origin.title))
            LabeledContent("Receptor", value: item.receivingStation.receiver.isEmpty ? "Sin anotar" : item.receivingStation.receiver)
            LabeledContent("Antena", value: item.receivingStation.antenna.isEmpty ? "Sin anotar" : item.receivingStation.antenna)
            LabeledContent("Sitio TX", value: item.transmitterName.isEmpty ? "Sin resolver" : item.transmitterName)
            Text(item.transmitterSource).font(.caption).foregroundStyle(.secondary)
            if let distance = item.distanceKm, let bearing = item.bearing {
                Text("TX → RX: \(distance, specifier: "%.0f") km · rumbo desde RX \(bearing, specifier: "%.0f")°")
            } else { Text("Completa TX y RX para mostrar el trayecto en el mapa.").foregroundStyle(.secondary) }
            if let broadcast = item.broadcast { Text("Horario previsto: \(broadcast.time) UTC · \(item.scheduleSeason ?? "")").font(.caption) }
            if let quality = item.quality { LabeledContent("Calidad manual", value: "\(quality) / 5") }
            Text(item.notes).textSelection(.enabled)
            if let forecast = item.forecast {
                DisclosureGroup("Pronóstico guardado · \(forecast.model)") { Text(forecast.assumptions).font(.caption).textSelection(.enabled) }
            }
            if let audioID = item.audioSessionID, let audio = store.sessions.first(where: { $0.id == audioID }) {
                Button("Ver audio adjunto: \(audio.title)") { store.category = "Todas"; store.selectedID = audioID; store.showsTrash = audio.isTrashed }
            } else { Text("Anotación manual sin audio adjunto.").font(.caption).foregroundStyle(.secondary) }
            HStack {
                if !item.isTrashed { Button("Editar / localizar") { store.editingObservation = item } }
                Button(item.isTrashed ? "Restaurar escucha" : "Mover a papelera") { store.trashObservation(item) }
            }.disabled(store.busy)
        }
    }
    private func detail(_ item: ReceptionSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled)
            LabeledContent("Tipo", value: AppLocalization.text(item.sourceKind.title))
            LabeledContent("Modo", value: AppLocalization.text(item.mode.title))
            LabeledContent("Archivo original", value: item.audio.originalFileName)
            LabeledContent("Audio", value: "\(item.audio.sampleRate.formatted()) Hz · \(item.audio.channels) canal(es) · \(item.audio.durationSeconds.formatted(.number.precision(.fractionLength(1)))) s")
            LabeledContent("Tamaño", value: ByteCountFormatter.string(fromByteCount: item.audio.byteCount, countStyle: .file))
            LabeledContent("Importación · UTC", value: utcText(item.importedAt))
            LabeledContent("Captura · UTC", value: item.capturedAt.map(utcText) ?? "Desconocida")
            LabeledContent("Demodulación", value: item.rf.modulation.rawValue)
            LabeledContent("Ancho RF", value: "\(item.rf.bandwidthHz.formatted()) Hz")
            LabeledContent("Frecuencia RF", value: item.rf.frequencyHz.map { "\(($0 / 1_000_000).formatted(.number.precision(.fractionLength(1...6)))) MHz" } ?? "Sin registrar")
            LabeledContent("Centro de audio", value: "\(item.settings.frequency.formatted()) Hz")
            if let source = item.rf.sourceDescription, !source.isEmpty { LabeledContent("Fuente indicada", value: source) }
            if let version = item.rf.engineVersion, !version.isEmpty { LabeledContent("Versión registrada", value: version) }
            Text("Al abrir se recupera la configuración completa del decodificador. La demodulación y la frecuencia RF describen la grabación; no sintonizan SDR++.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if item.isTrashed {
                    Button("Restaurar recepción") { store.restoreSelected() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Abrir y volver a decodificar") { store.openSelected(onOpen: onOpen) }
                        .buttonStyle(.borderedProminent).disabled(item.sourceKind != .audio || !item.mode.isAudioAvailable)
                    Button { store.trashSelected() } label: { Label("Mover a papelera", systemImage: "trash") }
                }
            }.disabled(store.busy)
            if !item.mode.isAudioAvailable { Text("El audio está guardado. Este modo todavía necesita un motor de recepción disponible.").font(.caption).foregroundStyle(.secondary) }
            if item.isTrashed { Text("La papelera conserva el audio y sus ajustes. No se elimina permanentemente desde esta pantalla.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func importAudio() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        panel.message = AppLocalization.text("El audio se copiará a la biblioteca con los ajustes actuales del receptor.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(url)
    }
    private func save(_ url: URL) {
        var metadata = rf
        let entered = frequencyMHz.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty {
            guard let value = Double(entered.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else {
                store.error = "Introduce una frecuencia RF válida en MHz, o deja el campo vacío si no se conoce."; return
            }
            metadata.frequencyHz = value * 1_000_000
        }
        let enteredTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = enteredTitle.isEmpty ? AppPreferencesStore.shared.values.suggestedName(original: url.deletingPathExtension().lastPathComponent, mode: mode) : enteredTitle
        store.importAudio(from: url, title: name, mode: mode, settings: settings,
                          rf: metadata, capturedAt: captureDateKnown ? captureDate : nil)
    }
    private func utcText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utc; formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
