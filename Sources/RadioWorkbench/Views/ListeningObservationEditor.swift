import SwiftUI
import RadioCore

struct ListeningObservationEditor: View {
    @Bindable var library: ReceptionLibraryStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var observation: ListeningObservation
    @ViewState private var frequency: String
    @ViewState private var txLatitude: String
    @ViewState private var txLongitude: String
    @ViewState private var rxLatitude: String
    @ViewState private var rxLongitude: String
    @ViewState private var selectedSite = -1
    @ViewState private var hasEnd = false
    @ViewState private var end = Date()
    @ViewState private var validation: String?
    let sites: [BroadcastSite]
    init(library: ReceptionLibraryStore, observation: ListeningObservation, sites: [BroadcastSite] = []) {
        self.library = library; self.sites = sites
        _observation = ViewState(initialValue: observation)
        _frequency = ViewState(initialValue: String(observation.frequencyHz / 1000))
        _txLatitude = ViewState(initialValue: observation.transmitter.map { String($0.latitude) } ?? "")
        _txLongitude = ViewState(initialValue: observation.transmitter.map { String($0.longitude) } ?? "")
        _rxLatitude = ViewState(initialValue: observation.receivingStation.location.map { String($0.latitude) } ?? "")
        _rxLongitude = ViewState(initialValue: observation.receivingStation.location.map { String($0.longitude) } ?? "")
        _hasEnd = ViewState(initialValue: observation.endedAt != nil)
        _end = ViewState(initialValue: observation.endedAt ?? observation.observedAt)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registrar escucha en biblioteca").font(.title2.weight(.semibold))
            Text("Anota lo que realmente escuchaste o intentaste recibir. El audio es opcional; el horario de la guía se conserva aparte.").foregroundStyle(.secondary)
            ScrollView {
                Form {
                    TextField("Emisora", text: $observation.stationName)
                    HStack { TextField("Frecuencia · kHz", text: $frequency); TextField("Modo SDR", text: $observation.modulation) }
                    DatePicker("Observación · UTC", selection: $observation.observedAt).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    Toggle("Registrar fin", isOn: $hasEnd)
                    if hasEnd { DatePicker("Fin · UTC", selection: $end).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!) }
                    Picker("Resultado", selection: $observation.outcome) {
                        ForEach(ListeningOutcome.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Calidad manual", selection: $observation.quality) {
                        Text("Sin valorar").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text("\($0) / 5").tag(Optional($0)) }
                    }
                    Section("Transmisor · opcional") {
                        if !sites.isEmpty {
                            Picker("Sitio de la guía", selection: $selectedSite) {
                                Text("Sin elegir / manual").tag(-1)
                                ForEach(sites.indices, id: \.self) { Text(sites[$0].name).tag($0) }
                            }.onChange(of: selectedSite) { _, index in
                                guard sites.indices.contains(index) else { return }
                                let site = sites[index]; txLatitude = String(site.latitude); txLongitude = String(site.longitude)
                                observation.transmitterName = site.name; observation.transmitterSource = "EiBi · sitio elegido por el usuario"
                            }
                        }
                        TextField("Nombre del sitio", text: $observation.transmitterName)
                        HStack { TextField("Latitud TX", text: $txLatitude); TextField("Longitud TX", text: $txLongitude) }
                        TextField("Fuente de las coordenadas", text: $observation.transmitterSource)
                        Text("Puedes guardar sin sitio TX. No se atribuye una posición a partir del país.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Receptor y antena en esta escucha") {
                        Picker("Origen", selection: $observation.receivingStation.origin) {
                            ForEach(ListeningOrigin.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if observation.receivingStation.origin == .remote {
                            Text("Indica la posición del receptor remoto; la posición de tu Mac no representa la antena del WebSDR.").font(.caption).foregroundStyle(.orange)
                        }
                        HStack { TextField("Latitud RX", text: $rxLatitude); TextField("Longitud RX", text: $rxLongitude) }
                        TextField("Receptor / ubicación remota", text: $observation.receivingStation.receiver)
                        TextField("Antena", text: $observation.receivingStation.antenna)
                        Text("Posición y antena quedan guardadas en esta ficha, aunque después cambies tu perfil.").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Audio existente · opcional", selection: $observation.audioSessionID) {
                        Text("Sin audio adjunto").tag(UUID?.none)
                        ForEach(library.sessions.filter { !$0.isTrashed }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    TextField("Notas · ruido, interferencias, equipo, certeza del sitio…", text: $observation.notes, axis: .vertical).lineLimit(3...6)
                    if let broadcast = observation.broadcast {
                        Text("Horario previsto: \(broadcast.time) UTC · \(broadcast.days) · \(observation.scheduleSeason ?? "") · no confirma emisión.").font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped)
            }
            if let error = validation ?? library.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if library.busy { ProgressView().controlSize(.small) }
                Button("Guardar escucha") { save() }.buttonStyle(.borderedProminent).disabled(library.busy)
            }
        }.padding(20).frame(width: 700, height: 720)
        .task { library.load() }
        .onChange(of: library.editingObservation) { _, value in if value == nil { dismiss() } }
    }
    private func save() {
        guard let kHz = RadioNumericText.number(frequency), kHz > 0 else { validation = "Revisa la frecuencia en kHz."; return }
        func coordinates(_ lat: String, _ lon: String) -> RadioLocation? { RadioLocation(latitude: lat, longitude: lon) }
        if (!txLatitude.isEmpty || !txLongitude.isEmpty) && coordinates(txLatitude, txLongitude) == nil { validation = "Completa ambas coordenadas TX o déjalas vacías."; return }
        if (!rxLatitude.isEmpty || !rxLongitude.isEmpty) && coordinates(rxLatitude, rxLongitude) == nil { validation = "Completa ambas coordenadas RX o déjalas vacías."; return }
        var item = observation
        item.stationName = item.stationName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.frequencyHz = kHz * 1000; item.transmitter = coordinates(txLatitude, txLongitude)
        item.receivingStation.location = coordinates(rxLatitude, rxLongitude)
        item.observedAt = Date(timeIntervalSince1970: floor(item.observedAt.timeIntervalSince1970))
        item.endedAt = hasEnd ? Date(timeIntervalSince1970: floor(end.timeIntervalSince1970)) : nil
        guard item.isValid else { validation = "Revisa nombre, límites de texto y fecha final (debe ser posterior al inicio)."; return }
        let matchesChosenSite = sites.indices.contains(selectedSite) && item.transmitter == RadioLocation(latitude: sites[selectedSite].latitude, longitude: sites[selectedSite].longitude)
        if item.transmitter != observation.transmitter && !matchesChosenSite {
            item.transmitterSource = "Entrada manual · " + String(item.transmitterSource.prefix(240))
        }
        library.saveObservation(item)
    }
}
