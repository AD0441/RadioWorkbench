import SwiftUI
import RadioCore

struct SatDumpOfflineView: View {
    @Bindable var store: SatDumpOfflineStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("LRPT con SatDump · archivo I/Q").font(.largeTitle.weight(.semibold))
                Text("Procesamiento local de una grabación compleja. La salida de audio de SDR++ y APT no sustituyen I/Q para LRPT.").foregroundStyle(.secondary)
                HStack { Button("Elegir SatDump.app…") { store.chooseApplication() }.disabled(store.busy); Text(store.application?.lastPathComponent ?? "Sin aplicación") }
                HStack { Button("Elegir I/Q…") { store.chooseInput() }.disabled(store.busy); Text(store.inputURL?.lastPathComponent ?? "Sin grabación") }
                HStack {
                    Picker("Señal", selection: $store.pipeline) { ForEach(LRPTPipeline.allCases) { Text($0.title).tag($0) } }.frame(width: 340).disabled(store.busy)
                    Picker("Formato I/Q", selection: $store.format) { ForEach(IQSampleFormat.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 190).disabled(store.busy)
                }
                HStack {
                    Text("Muestras/s")
                    TextField("Tasa", value: $store.sampleRate, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 130).disabled(store.busy)
                    Text("Centro RF MHz")
                    TextField("MHz", value: $store.frequencyMHz, format: .number).textFieldStyle(.roundedBorder).frame(width: 110).disabled(store.busy)
                }
                Toggle("Conozco la fecha de captura", isOn: $store.captureDateKnown).disabled(store.busy)
                if store.captureDateKnown { DatePicker("Captura · UTC", selection: $store.capturedAt).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).disabled(store.busy) }
                Text("Dos componentes I/Q intercaladas por muestra. No se adivina el formato por la extensión. La fecha y RF se conservan en la ficha del trabajo; no validan una georreferenciación. Sin TLE aportado no se confirma la posición del satélite.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Procesar I/Q offline") { store.start() }.buttonStyle(.borderedProminent).disabled(store.busy)
                    Button("Cancelar") { store.cancel() }.disabled(!store.busy)
                    Button("Ver productos en Finder") { store.showProducts() }.disabled(store.lastJobDirectory == nil)
                    if store.busy { ProgressView().controlSize(.small) }
                }
                if let value = store.stagePercent, store.busy { ProgressView("Etapa informada por SatDump: \(value.formatted(.number.precision(.fractionLength(1)))) %", value: value, total: 100) }
                Text(store.status).textSelection(.enabled)
                if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let result = store.result {
                    ForEach(Array(result.images.prefix(12)), id: \.path) { file in
                        if let image = NSImage(contentsOf: file) {
                            VStack(alignment: .leading) { Text(file.lastPathComponent).font(.caption); Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 360) }
                        }
                    }
                    Text("\(result.products.count) archivos incorporados al trabajo. La ausencia de imagen o un descriptor vacío no confirma recepción LRPT.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Registro de procesamiento") { Text(store.log.isEmpty ? "Sin registro todavía." : store.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Text("SatDump se ejecuta con red bloqueada y escrituras limitadas a este trabajo. No descarga TLE ni inicia SDR. Algunas versiones 1.2.3 terminan con código 1 incluso al completar el pipeline; el código y el registro se conservan. El progreso corresponde a una etapa, no al trabajo completo. Límite: 2 horas y 100 GB de entrada.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}
