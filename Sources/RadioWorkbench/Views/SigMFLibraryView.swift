import SwiftUI
import RadioCore

struct SigMFLibraryView: View {
    @Bindable var store: SigMFLibraryStore
    let onPrepare: (SigMFRecording) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Biblioteca I/Q · SigMF").font(.title2.weight(.semibold))
            Text("Muestras originales, frecuencia, tasa y captura UTC. La importación conserva las anotaciones, calcula SHA-512 y lo contrasta cuando el origen declara uno.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Importar SigMF…", systemImage: "square.and.arrow.down") { store.chooseImport() }.buttonStyle(.borderedProminent).disabled(store.busy)
                Button("Exportar par SigMF…") { store.exportSelected() }.disabled(store.busy || store.selected == nil || store.showsTrash)
                Toggle("Papelera", isOn: $store.showsTrash).toggleStyle(.button).disabled(store.busy).onChange(of: store.showsTrash) { store.select(nil) }
                if store.busy { ProgressView().controlSize(.small); Button("Cancelar") { store.cancel() } }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text(store.status).font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(selection: Binding(get: { store.selectedID }, set: { store.select($0) })) {
                    ForEach(store.visible) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.name).font(.headline)
                            Text("\(entry.datatype) · \(entry.sampleRate.formatted()) muestras/s · \(entry.duration.formatted(.number.precision(.fractionLength(1)))) s").font(.caption)
                        }.tag(entry.id)
                    }
                }.frame(minWidth: 260)
                ScrollView {
                    if let entry = store.selected {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.name).font(.title3)
                            LabeledContent("Formato", value: entry.datatype)
                            LabeledContent("Canales SigMF", value: String(entry.channels))
                            LabeledContent("Tamaño", value: ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
                            if let recording = store.selectedRecording {
                                Text(recording.description).textSelection(.enabled)
                                ForEach(recording.captures.prefix(16), id: \.sampleStart) { capture in
                                    Text("Muestra \(capture.sampleStart) · RF \(capture.frequencyHz.map { ($0 / 1_000_000).formatted() + " MHz" } ?? "sin declarar") · \(capture.date.map { $0.formatted(.iso8601) } ?? "fecha desconocida")").font(.caption)
                                }
                                if recording.satDumpFormat != nil, recording.captures.first?.date != nil, recording.captures.first?.frequencyHz != nil {
                                    Button("Preparar LRPT en SatDump") { onPrepare(recording) }
                                    Text("Copia los parámetros y el archivo; el procesamiento empieza cuando pulses Iniciar en SatDump.").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("SatDump requiere un canal I/Q cf32_le/ci16_le/ci8/cu8, una captura desde muestra 0, frecuencia y fecha conocidas. Esta grabación se puede conservar y exportar.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            DisclosureGroup("SHA-512 de la copia") { Text(entry.sha512).font(.caption.monospaced()).textSelection(.enabled) }
                            Button(entry.trashed ? "Restaurar" : "Mover a papelera") { store.changeTrash() }.disabled(store.busy)
                        }.padding(12)
                    } else { Text("Selecciona una grabación I/Q.").foregroundStyle(.secondary).padding() }
                }.frame(minWidth: 340)
            }.frame(minHeight: 320)
            Text("Soporte SigMF 1.0–1.2 para muestras crudas reales o complejas. No inicia un SDR ni convierte una grabación de audio en I/Q. La integración con SatDump no verifica por sí sola que el archivo contenga LRPT.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).task { store.load() }
    }
}
