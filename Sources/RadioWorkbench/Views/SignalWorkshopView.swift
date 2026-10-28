import SwiftUI
import RadioCore

struct SignalWorkshopView: View {
    @Bindable var store: SignalWorkshopStore
    let onDecode: (SignalReference, URL, AudioChannelSelection) -> Void
    @ViewState private var showsDecoderComparison = false
    private var referenceModes: [RadioMode] { RadioMode.allCases.filter { mode in SignalReference.allCases.contains { $0.mode == mode } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Taller de señales").font(.largeTitle.weight(.semibold))
                Text("Escucha y compara espectro y waterfall de audio. El catálogo incluye los 41 formatos SSTV y las variantes disponibles de los demás ejemplos.")
                    .foregroundStyle(.secondary)
                referenceSelection
                referenceDescription
                comparisonControls
                if DecoderComparison.supports(store.reference.mode), store.userURL != nil || store.referenceURL != nil {
                    Button("Comparar decodificación A/B…") { store.stopPlayback(); showsDecoderComparison = true }
                        .disabled(store.busy)
                }
                if store.busy {
                    HStack { ProgressView("Analizando hasta 12 segundos…"); Button("Cancelar") { store.cancelAnalysis() } }
                }
                if let error = store.error { Text(AppLocalization.text(error)).foregroundStyle(.red).textSelection(.enabled) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 16)], alignment: .leading, spacing: 16) {
                    probe("Referencia · \(store.referenceTitle)", result: store.referenceProbe, channel: store.referenceChannel)
                    probe(store.userURL?.lastPathComponent ?? "Tu grabación", result: store.userProbe, channel: store.channel)
                }
                HStack {
                    if let url = store.referenceURL {
                        Button(store.customReferenceURL == nil ? "Decodificar muestra de laboratorio" : "Probar ajustes con referencia propia") {
                            store.stopPlayback(); onDecode(store.reference, url, store.referenceChannel)
                        }
                    }
                    if let url = store.userURL {
                        Button("Probar ajustes con mi grabación") { store.stopPlayback(); onDecode(store.reference, url, store.channel) }
                    }
                }.disabled(store.busy)
                Text("Ambos gráficos representan audio, con escala fija de color de −100 a 0 dBFS. Comprueba los ejes: la frecuencia máxima depende también del muestreo. La comparación no normaliza amplitud ni mide potencia RF o SNR; una forma parecida no valida un protocolo. Los canales opuestos pueden cancelarse al mezclarlos.")
                    .font(.caption).foregroundStyle(.secondary)
                GroupBox("Configuración inicial para este ejemplo") {
                    let profile = store.reference.mode.receptionProfile(settings: store.reference.settings)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SDR: \(profile.modulation.rawValue) · filtro RF inicial \((profile.rfBandwidth / 1000).formatted()) kHz")
                        Text("Señal: \(store.reference.mode.signalModulation(settings: store.reference.settings))")
                        Text(AppLocalization.text(profile.audioBand))
                        Text(AppLocalization.text(profile.note)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Link("Artemis · catálogo externo", destination: URL(string: "https://aresvalley.github.io/Artemis/")!)
                    if let url = store.reference.mode.sourceURL { Link("Documentación del motor", destination: url) }
                }.font(.caption)
                Text("Las imágenes se calculan a demanda desde el WAV seleccionado y se conservan solo en memoria. No se copia la colección de imágenes ni sonidos de Artemis.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .task { if store.referenceProbe == nil { store.analyze() } }
        .onDisappear { store.stopPlayback(); store.cancelAnalysis() }
        .sheet(isPresented: $showsDecoderComparison) {
            if let url = store.userURL ?? store.referenceURL {
                DecoderComparisonView(mode: store.reference.mode, url: url, settings: comparisonSettings)
            }
        }
    }

    private var comparisonSettings: DecoderSettings {
        var settings = store.reference.settings
        settings.audioChannel = store.userURL == nil ? store.referenceChannel : store.channel
        return settings
    }

    private var referenceSelection: some View {
        HStack(alignment: .top) {
            Picker("Muestra y ajustes", selection: $store.reference) {
                ForEach(referenceModes) { mode in
                    Section(LocalizedStringKey(mode.title)) {
                        ForEach(SignalReference.allCases.filter { $0.mode == mode }) { reference in
                            Text(AppLocalization.text(reference.title)).tag(reference)
                        }
                    }
                }
            }.disabled(store.busy).onChange(of: store.reference) { store.referenceChanged() }
            Button("Referencia propia…") { store.chooseAudio(asReference: true) }.disabled(store.busy)
            if store.customReferenceURL != nil { Button("Restaurar muestra") { store.restoreLaboratoryReference() }.disabled(store.busy) }
        }
    }

    private var referenceDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.customReferenceURL != nil {
                Label("Referencia elegida por ti · protocolo sin verificar", systemImage: "person.crop.rectangle")
                    .font(.headline)
                Text("Los ajustes seleccionados siguen siendo los de \(store.reference.title). Una grabación propia no hereda el mensaje esperado ni la identidad de la muestra de laboratorio.")
                channelPicker("Canal de referencia", selection: $store.referenceChannel)
                    .onChange(of: store.referenceChannel) { store.analyze() }
                    .disabled(store.busy)
            } else {
                Text(AppLocalization.text(store.reference.explanation))
                Text("Resultado esperado: \(store.reference.expectedText)").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text(AppLocalization.text(store.reference.provenance)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var comparisonControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Escuchar referencia") { store.playReference() }
                Button("Escuchar mi audio") { store.playUser() }.disabled(store.userURL == nil)
                Button("Detener sonido") { store.stopPlayback() }
                Spacer()
                Button("Elegir mi audio…") { store.chooseAudio() }.disabled(store.busy)
            }
            HStack {
                channelPicker("Canal de mi archivo", selection: $store.channel).frame(maxWidth: 330)
                Button("Comparar") { store.analyze() }
                Button("Usar mi audio como referencia") { store.useUserAsReference() }.disabled(store.userURL == nil)
            }.disabled(store.busy)
            Text("Reproduce a volumen moderado, especialmente las señales de discriminador. Nada suena hasta pulsar Escuchar.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func channelPicker(_ title: String, selection: Binding<AudioChannelSelection>) -> some View {
        Picker(title, selection: selection) {
            Text("Mezcla").tag(AudioChannelSelection.mix)
            Text("Izquierdo / canal 1").tag(AudioChannelSelection.channel(0))
            Text("Derecho / canal 2").tag(AudioChannelSelection.channel(1))
        }
    }

    private func probe(_ title: String, result: SignalProbeResult?, channel: AudioChannelSelection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).lineLimit(2)
            if let result {
                SignalSpectrumPlot(result: result, height: 140)
                SignalWaterfallPlot(result: result, height: 180)
                Text("\(result.sampleRate.formatted()) Hz · \(result.channels) canales de origen · \(channel.label)")
                Text("\(result.secondsAnalyzed.formatted(.number.precision(.fractionLength(1)))) s analizados · RMS \(result.levelDB.formatted(.number.precision(.fractionLength(1)))) dBFS · \(result.clippedSamples) muestras al límite")
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary).frame(height: 370).overlay(Text("Sin análisis"))
            }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
