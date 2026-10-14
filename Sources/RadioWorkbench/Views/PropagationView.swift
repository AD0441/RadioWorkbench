import SwiftUI
import RadioCore

struct PropagationView: View {
    @Bindable var store: PropagationStore
    @Bindable var guide: BroadcastStore
    @Bindable var rbnStore: RBNStore
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
                    predictionForm(at: context.date)
                    if let error = store.calculationError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let report = store.report {
                        let current = store.input(origin: location, date: report.input.date) == report.input
                            && Calendar.current.isDate(context.date, equalTo: report.input.date, toGranularity: .hour)
                        HFPredictionPanel(report: report, current: current, originCountry: store.originCountry, targetCountry: store.targetCountry)
                    }
                    RadioActivityMapPanel(report: store.report, pskSpots: store.pskSnapshot?.spots ?? [], rbnSpots: rbnStore.spots)
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
        GroupBox("Tu ubicación") {
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
                Text("Coordenadas decimales: sur y oeste negativos. Se guardan en este Mac y sirven también para la guía de radios. Los cálculos y la consulta de la celda NOAA se hacen localmente.").font(.caption).foregroundStyle(.secondary)
                if location == nil { Text("Introduce una ubicación válida para ver el umbral de absorción local y calcular un enlace.").font(.caption).foregroundStyle(.orange) }
            }.padding(8)
        }
    }
    private func predictionForm(at date: Date) -> some View {
        GroupBox("Planificador HF · ITU-R P.533") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Dirección", selection: $store.listening) {
                    Text("Emisión desde tu ubicación").tag(false)
                    Text("Escucha del emisor remoto").tag(true)
                }.pickerStyle(.segmented)
                HStack {
                    field("Destino · latitud", text: $store.targetLatitude, hint: "Grados", width: 155)
                    field("Destino · longitud", text: $store.targetLongitude, hint: "Grados", width: 155)
                    Button("Usar emisora seleccionada") { store.useSelectedStation(guide) }
                    Spacer()
                }
                Text(store.targetName).font(.caption).foregroundStyle(.secondary)
                HStack {
                    field("Tu país · ISO 2", text: $store.originCountry, hint: "CL", width: 120)
                    field("País remoto · ISO 2", text: $store.targetCountry, hint: "ES", width: 140)
                    Text("Opcional: dos letras por país. Permite distinguir contacto nacional o internacional, incluso cerca de una frontera.").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 12) {
                    field("Potencia TX · W", text: $store.watts, hint: "100", width: 125)
                    field("Frecuencia · MHz", text: $store.frequencyMHz, hint: "7,1", width: 135)
                    field("Ancho · Hz", text: $store.bandwidth, hint: "2400", width: 110)
                    field("SNR requerido · dB", text: $store.requiredSNR, hint: "10", width: 135)
                    field("R12 mensual", text: $store.r12, hint: "1–311", width: 100)
                    Button("Usar R12 ITU") { store.useITUIndex(at: date) }
                }
                Text(store.wattsSource).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 12) {
                    field("Ganancia TX · dBi", text: $store.txGain, hint: "0", width: 140)
                    field("Ganancia RX · dBi", text: $store.rxGain, hint: "0", width: 140)
                    Picker("Ruido en RX", selection: $store.noise) {
                        Text("Ciudad").tag(0); Text("Residencial").tag(1); Text("Rural").tag(2); Text("Rural tranquilo").tag(3)
                    }.frame(maxWidth: .infinity)
                    if store.calculationBusy {
                        ProgressView().controlSize(.small)
                        Button("Cancelar") { store.cancelCalculation() }
                    } else {
                        Button("Calcular enlace") { store.calculate(origin: location, date: date) }.buttonStyle(.borderedProminent)
                    }
                }
                Text(store.r12Source).font(.caption).foregroundStyle(.secondary)
                Text("Predicción mensual por hora UTC, con antenas isotrópicas y ganancia constante; el ancho y SNR son requisitos de tu sistema. En Escucha, TX es el emisor remoto y RX tu ubicación: introduce su potencia como dato conocido o supuesto y el ruido de tu receptor.").font(.caption).foregroundStyle(.secondary)
                Text("Las frecuencias son puntos de cálculo. Elige frecuencia, modo y ancho que correspondan a tu estación. El modelo no mide potencia radiada ni confirma que una emisora esté transmitiendo.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
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
