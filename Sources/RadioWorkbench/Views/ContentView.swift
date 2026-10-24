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
            if receiver.destination == .broadcasts {
                BroadcastGuideView(guide: broadcasts, onPlanHF: { entry in
                    propagation.useStation(entry, guide: broadcasts); receiver.stop(); receiver.destination = .propagation
                }, onRecord: { entry in startObservation(entry: entry) })
            }
            else if receiver.destination == .propagation { PropagationView(store: propagation, guide: broadcasts, rbnStore: rbnStore, onRecord: { startObservation(entry: $0) }) {
                receiver.stop(); receiver.destination = .broadcasts
            } }
            else if receiver.destination == .consultations { RadioConsultationsView(store: consultations, receiver: receiver, guide: broadcasts, propagation: propagation, aprs: aprs, satellites: satellites) }
            else if receiver.destination == .library {
                ReceptionLibraryView(store: receiver.receptionLibrary, onRecord: { startObservation(entry: nil) }, currentAudioURL: receiver.lastURL,
                    mode: receiver.mode, settings: receiver.settings,
                    rf: ReceptionRFMetadata(modulation: receiver.rfModulation, bandwidthHz: receiver.rfBandwidth,
                        sourceDescription: receiver.source, engineVersion: "RadioWorkbench " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "desarrollo"))) {
                    item, url in receiver.openReception(item, url: url)
                }
            }
            else if receiver.destination == .rigctl { RigctlView(store: receiver.rigctl) }
            else if receiver.destination == .workshop {
                SignalWorkshopView(store: receiver.signalWorkshop) { reference, url, channel in
                    receiver.select(reference.mode); receiver.settings = reference.settings
                    receiver.settings.audioChannel = channel
                    let profile = reference.mode.receptionProfile(settings: receiver.settings)
                    receiver.rfModulation = profile.modulation; receiver.rfBandwidth = profile.rfBandwidth
                    receiver.decode(url)
                }
            }
            else if receiver.destination == .satDump { SatDumpOfflineView(store: receiver.satDumpOffline) }
            else if receiver.destination == .receptionMap { receptionMap }
            else if receiver.destination == .externalEvents { ReceptionEventsView(store: receiver.receptionEvents, showMap: false) }
            else { decoderPanel }
        }
        .toolbar {
            ToolbarItemGroup {
                if receiver.isDecoderSelected {
                Button { receiver.openAudio() } label: { Label("Abrir audio", systemImage: "folder") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.loadExample() } label: { Label(receiver.mode == .digitalVoice ? "Ejemplo M17 de datos…" : "Ejemplo", systemImage: "waveform.badge.plus") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.stop(); receiver.destination = .library } label: { Label("Guardar recepción", systemImage: "books.vertical") }
                    .disabled(receiver.lastURL == nil || receiver.busy)
                Button { receiver.startLive() } label: { Label("Escuchar", systemImage: "mic") }
                    .disabled(!receiver.mode.isAudioAvailable || receiver.busy)
                Button { receiver.stop() } label: { Label("Detener", systemImage: "stop.fill") }.disabled(!receiver.busy)
                }
            }
        }
        .sheet(item: Binding(get: { receiver.receptionLibrary.editingObservation }, set: { receiver.receptionLibrary.editingObservation = $0 })) { item in
            ListeningObservationEditor(library: receiver.receptionLibrary, observation: item,
                sites: item.broadcast.map { broadcasts.snapshot?.reference.siteCandidates(for: $0) ?? [] } ?? [])
        }
        .onChange(of: receiver.destination) { old, new in
            if old == .receptionMap && new != .consultations { aprs.stop() }
        }
        .task { await broadcasts.runAutoRefresh() }
        .onAppear { receiver.receptionLibrary.load(); aprs.receivedPosition = { [weak eventStore = receiver.receptionEvents] position in eventStore?.ingestAPRS(position) } }
        .task { await propagation.runAutoRefresh() }
    }
    private var decoderPanel: some View {
        HSplitView {
            Group {
                if receiver.mode.isImage { ImageReceiverView(receiver: receiver) }
                else if receiver.mode.isAudioAvailable { ReceiverView(receiver: receiver) }
                else { IntegrationView(mode: receiver.mode) }
            }.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            ReceptionInspectorView(mode: receiver.mode, settings: receiver.settings, canApply: !receiver.busy, onApply: { profile in
                guard !receiver.busy else { return }
                receiver.rfModulation = profile.modulation; receiver.rfBandwidth = profile.rfBandwidth
                if profile.center > 0 { receiver.settings.frequency = profile.center }
            }, onOpenWorkshop: { reference in
                receiver.stop(); receiver.signalWorkshop.reference = reference
                receiver.signalWorkshop.referenceChanged(); receiver.destination = .workshop
            })
        }
    }
    private func startObservation(entry: BroadcastEntry?) {
        let library = receiver.receptionLibrary
        library.error = nil
        var item = ListeningObservation(stationName: entry?.station ?? "Nueva escucha",
            frequencyHz: entry.map { $0.frequencyKHz * 1000 } ?? 7_100_000,
            modulation: entry?.modulation ?? receiver.rfModulation.rawValue,
            receivingStation: broadcasts.stationSnapshot)
        if let entry {
            item.broadcast = entry; item.scheduleSeason = broadcasts.snapshot?.season
            item.scheduleFetchedAt = broadcasts.snapshot?.fetchedAt
            if let site = broadcasts.snapshot?.reference.site(for: entry) {
                item.transmitter = RadioLocation(latitude: site.latitude, longitude: site.longitude)
                item.transmitterName = site.name; item.transmitterSource = "EiBi · sitio único de la ficha"
            }
            if propagation.listening, propagation.planningBroadcast?.id == entry.id,
               let report = propagation.report,
               propagation.input(origin: broadcasts.stationSnapshot.location, date: report.input.date) == report.input {
                item.forecast = ListeningForecast(model: "ITU-R P.533", computedAt: report.computedAt,
                    assumptions: propagation.hfPlanningDataText(origin: broadcasts.stationSnapshot.location, date: report.input.date))
            }
        }
        library.editingObservation = item
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
            ListeningMapView(library: receiver.receptionLibrary, events: receiver.receptionEvents)
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
