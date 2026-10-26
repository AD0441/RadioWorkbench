import SwiftUI
import AppKit
import RadioCore

struct DecoderComparisonView: View {
    let mode: RadioMode
    let url: URL
    @ViewState private var a: DecoderSettings
    @ViewState private var b: DecoderSettings
    @ViewState private var task: Task<Void, Never>?
    @ViewState private var result: DecoderComparisonResult?
    @ViewState private var error: String?
    @ViewState private var generation = UUID()
    @Environment(\.dismiss) private var dismiss
    init(mode: RadioMode, url: URL, settings: DecoderSettings) {
        self.mode = mode; self.url = url
        _a = ViewState(initialValue: settings); _b = ViewState(initialValue: settings)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Decodificación A/B · \(mode.title)").font(.title2)
                Text(url.lastPathComponent).textSelection(.enabled)
                Text("Mismo archivo, dos ejecuciones consecutivas. Ajusta el centro de audio y el canal; los demás parámetros conservan la configuración de la referencia. Máximo diez minutos y 1 GB.")
                HStack(alignment: .top, spacing: 24) { controls("A", settings: $a); controls("B", settings: $b) }.disabled(task != nil)
                HStack {
                    Button("Comparar A y B") { compare() }.disabled(task != nil)
                    if task != nil { ProgressView().controlSize(.small); Button("Cancelar") { cancel() } }
                    Spacer(); Button("Cerrar") { dismiss() }
                }
                if let error { Text(AppLocalization.text(error)).foregroundStyle(.red) }
                if let result {
                    Text("Audio: \(result.audioSeconds.formatted(.number.precision(.fractionLength(2)))) s. El tiempo depende del equipo y la carga; no es una medida de calidad.").font(.caption)
                    HStack(alignment: .top, spacing: 24) { output("A", run: result.a); output("B", run: result.b) }
                }
                Text("No se asigna un ganador ni un porcentaje de acierto sin un mensaje de referencia. Los registros externos son los retenidos por el monitor, no el total transmitido. No se reproduce ni modifica el audio.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width: 800, height: 620).onDisappear { cancel() }
    }
    private func controls(_ title: String, settings: Binding<DecoderSettings>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            TextField("Centro de audio (Hz)", value: settings.frequency, format: .number)
            Picker("Canal", selection: settings.audioChannel) {
                Text("Mezcla").tag(AudioChannelSelection.mix)
                Text("Izquierdo / 1").tag(AudioChannelSelection.channel(0))
                Text("Derecho / 2").tag(AudioChannelSelection.channel(1))
            }
            Toggle("Invertir", isOn: settings.inverted)
        }.frame(maxWidth: .infinity)
    }
    private func output(_ title: String, run: DecoderComparisonResult.Run) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) · \(run.seconds.formatted(.number.precision(.fractionLength(3)))) s de proceso").font(.headline)
            if let integrity = run.integrity {
                Text("\(integrity.check): \(integrity.accepted) \(integrity.unit) aceptados")
                if let rejected = integrity.rejected { Text("Rechazados: \(rejected)") }
                Text(integrity.note).font(.caption)
            } else { Text("Sin contador de integridad publicado por este motor.").font(.caption) }
            if run.retainedRecords > 0 { Text("Registros externos retenidos: \(run.retainedRecords)") }
            Text(run.text.isEmpty ? "Sin texto" : run.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func compare() {
        let token = UUID(); generation = token; result = nil; error = nil
        let first = a, second = b
        task = Task {
            do {
                let value = try await DecoderComparison().compare(url: url, mode: mode, a: first, b: second)
                guard generation == token, !Task.isCancelled else { return }
                result = value; task = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription; task = nil
            }
        }
    }
    private func cancel() { generation = UUID(); task?.cancel(); task = nil }
}
