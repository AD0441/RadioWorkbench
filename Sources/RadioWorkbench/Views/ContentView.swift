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
            case .broadcasts, .propagation, .consultations, .library, .externalEvents, .satDump, .rigctl, .workshop: receiver.stop(); receiver.destination = destination
            case .receptionMap: receiver.destination = destination
            case .decoder(let mode):
                if receiver.busy && receiver.mode == mode { receiver.destination = destination }
                else { receiver.select(mode) }
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
                    Label("Biblioteca de recepciones", systemImage: "books.vertical").tag(WorkbenchDestination.library)
                    Label("Mapa de recepciones", systemImage: "map").tag(WorkbenchDestination.receptionMap)
                    Label("LRPT · SatDump offline", systemImage: "antenna.radiowaves.left.and.right").tag(WorkbenchDestination.satDump)
                    Label("Sintonía optativa · Rigctl", systemImage: "dial.low").tag(WorkbenchDestination.rigctl)
                    Label("Eventos externos", systemImage: "tray.and.arrow.down").tag(WorkbenchDestination.externalEvents)
                    Label("Taller de señales", systemImage: "graduationcap").tag(WorkbenchDestination.workshop)
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
            if receiver.destination == .broadcasts { BroadcastGuideView(guide: broadcasts) { entry in
                propagation.useStation(entry, guide: broadcasts); receiver.stop(); receiver.destination = .propagation
            } }
            else if receiver.destination == .propagation { PropagationView(store: propagation, guide: broadcasts, rbnStore: rbnStore) {
                receiver.stop(); receiver.destination = .broadcasts
            } }
            else if receiver.destination == .consultations { RadioConsultationsView(store: consultations, receiver: receiver, guide: broadcasts, propagation: propagation, aprs: aprs, satellites: satellites) }
            else if receiver.destination == .library {
                ReceptionLibraryView(store: receiver.receptionLibrary, currentAudioURL: receiver.lastURL,
                    mode: receiver.mode, settings: receiver.settings,
                    rf: ReceptionRFMetadata(modulation: receiver.rfModulation, bandwidthHz: receiver.rfBandwidth,
                        sourceDescription: receiver.source, engineVersion: "RadioWorkbench " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "desarrollo"))) {
                    item, url in receiver.openReception(item, url: url)
                }
            }
            else if receiver.destination == .rigctl { RigctlView(store: receiver.rigctl) }
            else if receiver.destination == .workshop {
                SignalWorkshopView(store: receiver.signalWorkshop) { reference, url in
                    receiver.select(reference.mode); receiver.settings = reference.settings
                    if url == receiver.signalWorkshop.userURL { receiver.settings.audioChannel = receiver.signalWorkshop.channel }
                    receiver.decode(url)
                }
            }
            else if receiver.destination == .satDump { SatDumpOfflineView(store: receiver.satDumpOffline) }
            else if receiver.destination == .receptionMap { receptionMap }
            else if receiver.destination == .externalEvents { ReceptionEventsView(store: receiver.receptionEvents, showMap: false) }
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
                Button { receiver.stop(); receiver.destination = .library } label: { Label("Guardar recepción", systemImage: "books.vertical") }
                    .disabled(receiver.lastURL == nil || receiver.busy)
                Button { receiver.startLive() } label: { Label("Escuchar", systemImage: "mic") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.stop() } label: { Label("Detener", systemImage: "stop.fill") }.disabled(!receiver.busy)
                }
            }
        }
        .onChange(of: receiver.destination) { old, new in
            if old == .receptionMap && new != .consultations { aprs.stop() }
        }
        .task { await broadcasts.runAutoRefresh() }
        .onAppear { aprs.receivedPosition = { [weak eventStore = receiver.receptionEvents] position in eventStore?.ingestAPRS(position) } }
        .task { await propagation.runAutoRefresh() }
    }
    private var receptionMap: some View {
        VStack(alignment: .leading, spacing: 4) {
            if receiver.busy {
                HStack {
                    Label("Recepción activa: " + receiver.source, systemImage: "waveform")
                    Spacer(); Button("Detener recepción") { receiver.stop() }
                }.font(.caption).padding(.horizontal, 24).padding(.top, 12)
            }
            if aprs.connected {
                HStack {
                    Label("APRS-IS conectado · " + aprs.status, systemImage: "network")
                    Spacer(); Button("Desconectar APRS-IS") { aprs.stop() }
                }.font(.caption).padding(.horizontal, 24)
            }
            ReceptionEventsView(store: receiver.receptionEvents)
        }
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
