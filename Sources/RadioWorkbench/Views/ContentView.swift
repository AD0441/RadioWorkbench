import SwiftUI
import RadioCore

struct ContentView: View {
    @Bindable var receiver: ReceiverStore
    @Bindable var broadcasts: BroadcastStore
    @Bindable var propagation: PropagationStore
    @Bindable var rbnStore: RBNStore
    @Bindable var consultations: RadioConsultationStore
    @Bindable var aprs: APRSISStore
    @Bindable var satellites: SatelliteConsultationStore
    private var selection: Binding<WorkbenchDestination> {
        Binding(get: { receiver.destination }, set: { destination in
            switch destination {
            case .broadcasts, .propagation, .consultations: receiver.stop(); receiver.destination = destination
            case .decoder(let mode): receiver.select(mode)
            }
        })
    }
    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Consulta") {
                    Label("Guía de radios", systemImage: "globe.americas").tag(WorkbenchDestination.broadcasts)
                    Label("Condiciones y propagación", systemImage: "sun.max").tag(WorkbenchDestination.propagation)
                    Label("Consultas de radio", systemImage: "magnifyingglass").tag(WorkbenchDestination.consultations)
                }
                ForEach(["Audio · disponible", "Imágenes", "Marítimo y navegación", "Otros modos"], id: \.self) { family in
                    Section(family) {
                        ForEach(RadioMode.allCases.filter { $0.family == family }) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(WorkbenchDestination.decoder(mode))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("RadioWorkbench")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            VStack(alignment: .leading, spacing: 4) {
                Label("Apple Silicon", systemImage: "cpu").font(.caption.weight(.medium))
                Text("Recepción local · arm64").font(.caption).foregroundStyle(.secondary)
            }.padding()
        } detail: {
            if receiver.destination == .broadcasts { BroadcastGuideView(guide: broadcasts) }
            else if receiver.destination == .propagation { PropagationView(store: propagation, guide: broadcasts, rbnStore: rbnStore) }
            else if receiver.destination == .consultations { RadioConsultationsView(store: consultations, receiver: receiver, guide: broadcasts, propagation: propagation, aprs: aprs, satellites: satellites) }
            else if receiver.mode.isImage { ImageReceiverView(receiver: receiver) }
            else if receiver.mode.isAudioAvailable { ReceiverView(receiver: receiver) }
            else { IntegrationView(mode: receiver.mode) }
        }
        .toolbar {
            ToolbarItemGroup {
                if receiver.isDecoderSelected {
                Button { receiver.openAudio() } label: { Label("Abrir audio", systemImage: "folder") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.loadExample() } label: { Label("Ejemplo", systemImage: "waveform.badge.plus") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.startLive() } label: { Label("Escuchar", systemImage: "mic") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.stop() } label: { Label("Detener", systemImage: "stop.fill") }.disabled(!receiver.busy)
                }
            }
        }
        .task { await broadcasts.runAutoRefresh() }
        .task { await propagation.runAutoRefresh() }
    }
}

struct PreferencesView: View {
    var body: some View {
        Form {
            LabeledContent("Motor", value: "Swift + Accelerate · arm64")
            LabeledContent("Entrada en vivo", value: "Selector en Recepción")
            Text("Elige el receptor USB o dispositivo virtual en Entrada de audio. La selección se aplica a esta app y la captura comienza al pulsar Escuchar.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}
