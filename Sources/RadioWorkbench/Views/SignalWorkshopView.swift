import SwiftUI
import RadioCore

struct SignalWorkshopView: View {
    @Bindable var store: SignalWorkshopStore
    let onDecode: (SignalReference, URL) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Taller de señales").font(.largeTitle.weight(.semibold))
                Text("Compara una referencia sintética conocida con tu grabación, escucha su sonido y prueba sus ajustes.").foregroundStyle(.secondary)
                Picker("Referencia", selection: $store.reference) { ForEach(SignalReference.allCases) { Text($0.title).tag($0) } }
                    .disabled(store.busy).onChange(of: store.reference) { store.analyze() }
                Text(store.reference.explanation)
                Text("Mensaje de referencia: \(store.reference.expectedText)").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Escuchar referencia") { store.playReference() }
                    Button("Detener sonido") { store.stopPlayback() }
                    Button("Elegir mi audio…") { store.chooseAudio() }.disabled(store.busy)
                    Picker("Canal de mi archivo", selection: $store.channel) {
                        Text("Mezcla").tag(AudioChannelSelection.mix)
                        Text("Izquierdo / canal 1").tag(AudioChannelSelection.channel(0))
                        Text("Derecho / canal 2").tag(AudioChannelSelection.channel(1))
                    }.frame(width: 260).disabled(store.busy)
                    Button("Comparar") { store.analyze() }.disabled(store.busy)
                }
                if store.busy { ProgressView("Analizando los primeros 12 segundos…") }
                if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                HStack(alignment: .top, spacing: 16) {
                    probe("Referencia · \(store.reference.title)", result: store.referenceProbe)
                    probe(store.userURL?.lastPathComponent ?? "Tu grabación", result: store.userProbe)
                }
                HStack {
                    if let url = store.referenceURL { Button("Decodificar referencia") { store.stopPlayback(); onDecode(store.reference, url) } }
                    if let url = store.userURL { Button("Probar esos ajustes con mi archivo") { store.stopPlayback(); onDecode(store.reference, url) } }
                }.disabled(store.busy)
                Text("La comparación usa potencia espectral media y dBFS de audio, sin normalizar amplitud. Las frecuencias de los ejes dependen de cada tasa de muestreo. Un aspecto parecido no demuestra el protocolo ni una recepción correcta. No clasifica señales automáticamente. Mezclar canales opuestos puede cancelar la señal: compara también un canal individual.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.task { if store.referenceProbe == nil { store.analyze() } }.onDisappear { store.stopPlayback() }
    }
    private func probe(_ title: String, result: SignalProbeResult?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let result {
                Canvas { context, size in
                    var path = Path()
                    for index in result.bins.indices {
                        let point = CGPoint(x: Double(index) / Double(result.bins.count) * size.width,
                                            y: (1 - min(1, max(0, (Double(result.bins[index]) + 100) / 100))) * size.height)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(.cyan), lineWidth: 1.5)
                }.frame(height: 180).padding(10).background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                HStack { Text("0 Hz"); Spacer(); Text("\(Int(result.upperFrequency)) Hz") }.font(.caption)
                Text("\(result.sampleRate.formatted()) Hz · \(result.channels) ch · \(result.secondsAnalyzed.formatted(.number.precision(.fractionLength(1)))) s analizados")
                Text("RMS \(result.levelDB.formatted(.number.precision(.fractionLength(1)))) dBFS · \(result.clippedSamples) muestras al límite")
            } else { RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(height: 180).overlay(Text("Sin análisis")) }
        }.font(.caption).frame(maxWidth: .infinity)
    }
}
