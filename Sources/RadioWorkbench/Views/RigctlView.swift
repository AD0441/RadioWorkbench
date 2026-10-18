import SwiftUI
import RadioCore

struct RigctlView: View {
    @Bindable var store: RigctlStore
    var body: some View {
        Form {
            Text("Sintonía optativa · Rigctl").font(.largeTitle.weight(.semibold))
            Text("\(store.source). Revisa la frecuencia de dial, modo y ancho antes de enviarlos.").foregroundStyle(.secondary)
            Toggle("Habilitar esta conexión local", isOn: $store.enabled).disabled(store.busy)
            LabeledContent("Servidor", value: "127.0.0.1 · sin conexión automática")
            TextField("Puerto", value: $store.port, format: .number.grouping(.never)).disabled(store.busy)
            TextField("Frecuencia de dial · MHz", text: $store.frequencyMHz).disabled(store.busy)
            Picker("Modo", selection: $store.modulation) { ForEach(RFModulation.allCases.filter { $0 != .iq }) { Text($0.rawValue).tag($0) } }.disabled(store.busy)
            TextField("Ancho RF · Hz", value: $store.bandwidthHz, format: .number.grouping(.never)).disabled(store.busy)
            HStack {
                Button("Comprobar conexión") { store.perform(apply: false) }
                Button("Enviar frecuencia, modo y ancho") { store.perform(apply: true) }.buttonStyle(.borderedProminent)
            }.disabled(!store.enabled || store.busy)
            if store.busy { ProgressView(); Button("Cancelar") { store.cancel() } }
            Text(store.status).textSelection(.enabled)
            if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let state = store.state { LabeledContent("Última lectura", value: "\(state.frequencyHz.formatted()) Hz · \(state.mode) · \(state.bandwidthHz) Hz") }
            Text("Cada acción abre una conexión y la cierra al terminar. Se verifica el estado después de enviar: algunos servidores contestan éxito con sintonía desactivada. No envía PTT, órdenes de grabación, barrido ni Doppler. Ajusta manualmente cualquier desplazamiento de dial que requiera el modo, como radiofax.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}
