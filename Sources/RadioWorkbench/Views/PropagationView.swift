import SwiftUI
import AppKit
import RadioCore

struct PropagationView: View {
    @Bindable var store: PropagationStore
    @Bindable var guide: BroadcastStore
    @Bindable var rbnStore: RBNStore
    let onRecord: (BroadcastEntry) -> Void
    let onOpenGuide: () -> Void
    private var location: RadioLocation? { RadioLocation(latitude: guide.latitude, longitude: guide.longitude) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    locationForm(at: context.date)
                    BandInformationPanel(store: store, location: location, date: context.date)
                    SpaceWeatherPanel(snapshot: store.weather, errors: store.sourceErrors, location: location, date: context.date)
                    NoaaThreeDayForecastPanel(forecast: store.noaaForecast, status: store.noaaForecastStatus)
                    IonosondePanel(snapshot: store.ionosphere, status: store.ionosphereStatus, location: location, date: context.date)
                    PSKReporterPanel(store: store, location: location, date: context.date)
                    RBNPanel(store: rbnStore)
                    predictionForm(at: store.planningTime(at: context.date))
                    if let error = store.calculationError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let report = store.report, !store.listening || store.estimatesReception {
                        let current = store.input(origin: location, date: report.input.date) == report.input
                            && BroadcastCalendar.utc.isDate(store.planningTime(at: context.date), equalTo: report.input.date, toGranularity: .hour)
                        HFPredictionPanel(report: report, current: current, originCountry: store.originCountry, targetCountry: store.targetCountry,
                                          listening: store.listening, direction: store.listening ? "Emisora → receptor local" : "A → B")
                        if let returning = store.returnReport {
                            let reverseCurrent = store.reverseInput(origin: location, date: returning.input.date) == returning.input && current
                            if let limiting = store.limitingDirection, reverseCurrent { Text(limiting).font(.headline) }
                            else if !reverseCurrent { Label("Enlace bilateral anterior: recalcula ambas direcciones.", systemImage: "arrow.clockwise").foregroundStyle(.orange) }
                            DisclosureGroup("Resultado del regreso B → A") {
                                HFPredictionPanel(report: returning, current: reverseCurrent, originCountry: store.targetCountry,
                                                  targetCountry: store.originCountry, listening: false, direction: "B → A")
                            }
                        }
                    }
                    RadioActivityMapPanel(report: (!store.listening || store.estimatesReception) ? store.report : nil, pskSpots: store.pskSnapshot?.spots ?? [], rbnSpots: rbnStore.spots)
                    TerrainLinkPanel(store: store, defaultOrigin: location,
                                     defaultDestination: RadioLocation(latitude: store.targetLatitude, longitude: store.targetLongitude))
                    sourceLinks
                }.padding(20).frame(maxWidth: 1100, alignment: .leading)
            }
        }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Condiciones y propagación").font(.largeTitle.weight(.semibold))
                Text("Clima espacial reciente y planificación de enlaces por banda").foregroundStyle(.secondary)
                Text(store.weatherStatus).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await store.refresh(forceIndices: true) } } label: { Label("Actualizar", systemImage: "arrow.clockwise") }.disabled(store.weatherBusy)
            if store.weatherBusy { ProgressView().controlSize(.small) }
        }
    }
    private func locationForm(at date: Date) -> some View {
        GroupBox("Perfil de recepción · ubicación y antena") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    field("Latitud", text: $guide.latitude, hint: "−33,45", width: 145)
                    field("Longitud", text: $guide.longitude, hint: "−70,67", width: 145)
                    Button("Guardar ubicación") { guide.saveLocation() }.disabled(location == nil)
                    Spacer()
                    if let location {
                        let sun = location.solarElevation(at: date)
                        VStack(alignment: .trailing) {
                            Label(sun >= 0 ? "Día" : sun >= -6 ? "Crepúsculo" : "Noche", systemImage: sun >= 0 ? "sun.max" : "moon")
                            Text("Sol \(sun, specifier: "%.1f")°").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    TextField("Receptor", text: $guide.receiverName).textFieldStyle(.roundedBorder)
                    TextField("Antena", text: $guide.antennaName).textFieldStyle(.roundedBorder)
                    Picker("Origen", selection: $guide.listeningOrigin) {
                        ForEach(ListeningOrigin.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Text("Coordenadas decimales: sur y oeste negativos. Se guardan en este Mac y sirven también para la guía de radios. Los cálculos y la consulta de la celda NOAA se hacen localmente.").font(.caption).foregroundStyle(.secondary)
                if location == nil { Text("Introduce una ubicación válida para ver el umbral de absorción local y calcular un enlace.").font(.caption).foregroundStyle(.orange) }
            }.padding(8)
        }
    }
    private func predictionForm(at date: Date) -> some View {
        GroupBox("Planificador HF") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Uso", selection: $store.listening) {
                    Text("Escucha de emisoras · RX").tag(true)
                    Text("Enlace entre estaciones · TX/RX").tag(false)
                }.pickerStyle(.segmented)
                HStack {
                    Toggle("Usar hora actual", isOn: $store.usesCurrentPlanningTime)
                    DatePicker("Fecha y hora UTC", selection: $store.planningDate, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).disabled(store.usesCurrentPlanningTime)
                }
                plannerEndpoints(at: date)
                if store.listening {
                    Toggle("Estimar recepción con ITU-R P.533 · requiere supuestos técnicos", isOn: $store.estimatesReception)
                    Text("La ficha de escucha funciona sin conocer la potencia remota. P.533 añade una estimación mensual, si dispones de datos del transmisor y de tu receptor.").font(.caption).foregroundStyle(.secondary)
                }
                if !store.listening || store.estimatesReception { predictionAssumptions(at: date) }
                if store.listening, let entry = store.planningBroadcast {
                    Button("Registrar resultado de esta escucha en biblioteca…", systemImage: "books.vertical") { onRecord(entry) }
                }
                Button(store.listening ? "Copiar ficha de escucha" : "Copiar datos del enlace") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.hfPlanningDataText(origin: location, date: date), forType: .string)
                }
            }.padding(8)
        }
    }
    private func plannerEndpoints(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.listening ? "Receptor: perfil local de arriba · TX: emisora remota" : "Estación A: perfil local de arriba · estación B: coordenadas remotas").font(.headline)
            HStack {
                field(store.listening ? "Emisor remoto · latitud" : "Estación B · latitud", text: $store.targetLatitude, hint: "Grados", width: 165)
                field(store.listening ? "Emisor remoto · longitud" : "Estación B · longitud", text: $store.targetLongitude, hint: "Grados", width: 165)
                field("Frecuencia · MHz", text: $store.frequencyMHz, hint: "9,655 MHz", width: 145)
            }
            HStack {
                Button("Planificar escucha de emisora seleccionada") { store.useSelectedStation(guide) }.disabled(guide.selectedEntry == nil)
                Button("Abrir guía") { onOpenGuide() }
            }
            if !store.stationTransferNotice.isEmpty && store.listening { Text(store.stationTransferNotice).font(.caption).textSelection(.enabled) }
            if store.listening && !store.stationSites.isEmpty {
                HStack {
                    Picker("Sitio TX", selection: $store.selectedStationSite) {
                        Text("Elegir sitio / manual").tag(Int?.none)
                        ForEach(store.stationSites.indices, id: \.self) { Text(store.stationSites[$0].name).tag(Optional($0)) }
                    }.frame(maxWidth: 450)
                    Button("Usar sitio") { store.useChosenStationSite() }.disabled(store.selectedStationSite == nil)
                }
            }
            Text(store.targetName).font(.caption).foregroundStyle(.secondary)
            if let frequency = RadioNumericText.frequencyMHz(store.frequencyMHz), !(1.6...30).contains(frequency) {
                Text("Esta frecuencia queda fuera de P.533 (1,6–30 MHz). La ficha y el registro de escucha siguen disponibles.").font(.caption).foregroundStyle(.orange)
            }
            Text(store.pathSummary(origin: location, date: date)).font(.callout).textSelection(.enabled)
            if store.listening, let entry = store.planningBroadcast {
                Text("Horario previsto de la guía: \(entry.time) UTC · días \(entry.days). \(BroadcastCalendar.activity(entry, at: date, season: guide.snapshot?.season ?? "").rawValue). Sintonía inicial: \(entry.tuningSuggestion)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                field("País A / local · ISO 2", text: $store.originCountry, hint: "CL", width: 140)
                field("País B / remoto · ISO 2", text: $store.targetCountry, hint: "ES", width: 150)
                Text("La iluminación es geometría solar aproximada; no mide apertura de banda.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func predictionAssumptions(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.listening ? "Emisora → tu receptor" : "A → B · TX en A, recepción en B").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 10) {
                field(store.listening ? "Potencia remota · W" : "Potencia TX A · W", text: $store.watts, hint: "Dato o supuesto", width: 140)
                field(store.listening ? "Ancho RX local · Hz" : "Ancho RX B · Hz", text: $store.bandwidth, hint: "2400", width: 140)
                field(store.listening ? "SNR local requerido · dB" : "SNR RX B · dB", text: $store.requiredSNR, hint: "10", width: 140)
                field(store.listening ? "Ganancia TX remota · dBi" : "Ganancia TX A · dBi", text: $store.txGain, hint: "0", width: 140)
                field(store.listening ? "Ganancia RX local · dBi" : "Ganancia RX B · dBi", text: $store.rxGain, hint: "0", width: 140)
                noisePicker(store.listening ? "Ruido RX local" : "Ruido RX B", selection: $store.noise)
            }
            Text(store.wattsSource).font(.caption).foregroundStyle(.secondary)
            if store.listening, let candidate = store.stationPowerCandidate, let power = candidate.powerKW {
                HStack {
                    Text("HFCC candidato: \(power) kW · sitio \(candidate.siteCode). Verifica que sea el mismo transmisor.").font(.caption)
                    Button("Usar esta potencia como supuesto") { store.useCandidatePowerAsAssumption() }
                }
            }
            if !store.listening { returnAssumptions }
            HStack {
                field("R12 mensual · compartido", text: $store.r12, hint: "0–311", width: 150)
                Button("Usar R12 ITU") { store.useITUIndex(at: date) }
                if store.r12MonthMismatch(at: date) { Button("Usarlo como supuesto manual") { store.useManualR12() } }
            }
            Text(store.r12Source).font(.caption).foregroundStyle(.secondary)
            let missing = store.inputProblems(origin: location, date: date)
            if !missing.isEmpty { Text(missing.joined(separator: "\n")).font(.caption).foregroundStyle(.orange) }
            if store.calculationBusy {
                HStack { ProgressView().controlSize(.small); Button("Cancelar") { store.cancelCalculation() } }
            } else {
                Button(store.listening ? "Estimar recepción P.533" : "Calcular A → B y B → A") { store.calculate(origin: location, date: date) }
                    .buttonStyle(.borderedProminent)
            }
            Text("P.533: 1,6–30 MHz, mediana mensual por hora UTC, antenas con ganancia constante. Ancho equivalente de ruido RX y SNR son supuestos del sistema; el motor no valida BER ni audio AM/DRM. Los resultados no confirman emisión ni propagación en tiempo real.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var returnAssumptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("B → A · TX en B, recepción en A").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 10) {
                field("Potencia TX B · W", text: $store.returnWatts, hint: "100", width: 140)
                field("Ganancia TX B · dBi", text: $store.returnTXGain, hint: "0", width: 140)
                field("Ganancia RX A · dBi", text: $store.returnRXGain, hint: "0", width: 140)
                field("Ancho RX A · Hz", text: $store.returnBandwidth, hint: "2400", width: 140)
                field("SNR RX A · dB", text: $store.returnRequiredSNR, hint: "10", width: 140)
                noisePicker("Ruido RX A", selection: $store.returnNoise)
            }
            Text("Cada dirección conserva potencia, antenas y condiciones RX propias. La menor BCR orienta sobre el sentido limitante; no se multiplican ambas disponibilidades.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func noisePicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("Ciudad").tag(0); Text("Residencial").tag(1); Text("Rural").tag(2); Text("Rural tranquilo").tag(3)
        }
    }
    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fuentes para contrastar las condiciones").font(.headline)
            HStack {
                Link("NOAA D-RAP", destination: URL(string: "https://www.swpc.noaa.gov/products/d-region-absorption-predictions-d-rap")!)
                Link("ITU-R P.533", destination: URL(string: "https://www.itu.int/rec/R-REC-P.533")!)
                Link("Índices R12", destination: SpaceWeatherSource.indices.url)
                Link("VOACAP", destination: URL(string: "https://www.voacap.com/radcom/")!)
            }
            HStack {
                Link("PSK Reporter", destination: URL(string: "https://pskreporter.info/pskmap.html")!)
                Link("Reverse Beacon Network", destination: URL(string: "https://www.reversebeacon.net/")!)
                Link("Ionosondas GIRO", destination: URL(string: "https://giro.uml.edu/didbase/")!)
            }
            Text("PSK Reporter aporta cuadrículas observadas; RBN aporta actividad global por frecuencia y modo. Se comparan con la ruta calculada cuando existen datos, manteniendo observaciones y predicciones identificadas por separado.").font(.caption).foregroundStyle(.secondary)
        }.font(.caption)
    }
    private func field(_ title: String, text: Binding<String>, hint: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }.frame(width: width)
    }
}
