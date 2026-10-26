import SwiftUI
import RadioCore

struct TerrainLinkPanel: View {
    @Bindable var store: PropagationStore
    let defaultOrigin: RadioLocation?
    let defaultDestination: RadioLocation?

    private var marginDB: Double? {
        guard let result = store.terrainResult, let threshold = store.number(store.terrainSensitivityDBm) else { return nil }
        return result.receivedPowerDBm - threshold
    }

    var body: some View {
        GroupBox("VHF/UHF · enlace punto a punto con relieve") {
            VStack(alignment: .leading, spacing: 12) {
                endpointFields.disabled(store.terrainBusy || store.terrainCoverageBusy)

                HStack(spacing: 12) {
                    Button { store.copyLocationToTerrainOrigin(defaultOrigin) } label: {
                        Label("Copiar ubicación guardada al origen", systemImage: "location")
                    }.disabled(defaultOrigin == nil)
                    Button { store.copyHFEndpointToTerrainTarget() } label: {
                        Label("Copiar destino del planificador HF", systemImage: "arrow.down.to.line")
                    }.disabled(defaultDestination == nil)
                }
                if let km = store.terrainHorizon {
                    Label("Referencia de Tierra lisa (AGL): \(km, specifier: "%.1f") km · el relieve se calcula debajo", systemImage: "circle.dashed")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }

                TerrainLinkMapPanel(store: store)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 12) {
                    field("Frecuencia · MHz", text: $store.terrainFrequencyMHz, hint: "144,39", width: 140)
                    field("Potencia TX · W", text: $store.terrainWatts, hint: "10", width: 130)
                    field("Ganancia TX · dBi", text: $store.terrainTxGain, hint: "0", width: 140)
                    field("Ganancia RX · dBi", text: $store.terrainRxGain, hint: "0", width: 140)
                    field("Umbral RX · dBm", text: $store.terrainSensitivityDBm, hint: "−110", width: 140)
                    Picker("Clima ITM", selection: $store.terrainClimate) {
                        ForEach(ITMClimate.allCases) { climate in Text(AppLocalization.text(climate.title)).tag(climate) }
                    }.frame(minWidth: 200)
                    Picker("Polarización", selection: $store.terrainVerticalPolarization) {
                        Text("Vertical").tag(true); Text("Horizontal").tag(false)
                    }.frame(width: 145)
                    Link("NTIA ITM / Longley–Rice", destination: URL(string: "https://github.com/NTIA/itm")!)
                }.disabled(store.terrainBusy || store.terrainCoverageBusy)

                HStack(spacing: 12) {
                    Button {
                        Task { await store.calculateTerrain() }
                    } label: {
                        if store.terrainBusy { ProgressView().controlSize(.small) }
                        else { Label("Calcular relieve y enlace", systemImage: "mountain.2") }
                    }.buttonStyle(.borderedProminent).disabled(store.terrainBusy || store.terrainCoverageBusy)
                    Text(AppLocalization.text(store.terrainStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    field("Radio de análisis · km", text: $store.terrainCoverageMaximumKm, hint: "100", width: 145)
                        .disabled(store.terrainCoverageBusy || store.terrainBusy)
                    Picker("Malla", selection: $store.terrainCoverageQuality) {
                        ForEach(TerrainCoverageQuality.allCases) { quality in Text(AppLocalization.text(quality.title)).tag(quality) }
                    }.frame(width: 230).disabled(store.terrainCoverageBusy || store.terrainBusy)
                    Button {
                        Task { await store.calculateTerrainCoverage() }
                    } label: {
                        if store.terrainCoverageBusy { ProgressView().controlSize(.small) }
                        else { Label("Calcular malla con terreno", systemImage: "map") }
                    }.buttonStyle(.bordered).disabled(store.terrainCoverageBusy || store.terrainBusy)
                    if store.terrainCoverageBusy {
                        ProgressView(value: store.terrainCoverageProgress)
                            .frame(width: 120)
                        Button("Cancelar") { store.cancelTerrainCoverage() }
                    }
                }
                Text(AppLocalization.text(store.terrainCoverageStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Cada celda evalúa su propio enlace ITM con el relieve completo; se conservan sombras y recuperaciones en cumbres. La malla cubre un área de análisis de 5–200 km, con paso visible y DEM de teselas Mapzen/SRTM. No se rellena hasta el punto más lejano.")
                    .font(.caption2).foregroundStyle(.secondary)

                if let result = store.terrainResult {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 8) {
                        Label("Pérdida ITM: \(result.basicTransmissionLossDB, specifier: "%.1f") dB", systemImage: "arrow.left.arrow.right")
                        Label("Potencia en RX: \(result.receivedPowerDBm, specifier: "%.1f") dBm", systemImage: "waveform.path")
                        if let marginDB {
                            Label("Margen frente al umbral: \(marginDB >= 0 ? "+" : "")\(marginDB, specifier: "%.1f") dB", systemImage: marginDB >= 0 ? "checkmark.radiowaves.left.and.right" : "exclamationmark.radiowaves.left.and.right")
                        }
                        Label(AppLocalization.text(result.propagationMode), systemImage: "mountain.2")
                        Text("Irregularidad del terreno: \(result.terrainIrregularityMeters, specifier: "%.0f") m · avisos ITM: \(result.warningFlags)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.font(.callout).textSelection(.enabled)
                    if result.warningFlags != 0 {
                        Text("Avisos del modelo: " + TerrainITMWarning.descriptions(flags: result.warningFlags).joined(separator: "; "))
                            .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }

                Text("Las alturas TX/RX se ingresan sobre el suelo (AGL); NTIA ITM las combina con las elevaciones del terreno AMSL y modela difracción en montañas. El corte muestra el terreno y la línea directa: una obstrucción no significa silencio total. La malla es una estimación al umbral RX, no una probabilidad ni garantía; no incluye edificios, vegetación, patrón de antena, pérdidas de cable, interferencia, ductos o esporádica E. La malla descarga DEM solo al solicitarla y conserva teselas en caché; las celdas sin datos quedan transparentes. Las alturas negativas de batimetría se aproximan a nivel del mar.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("NTIA · código y licencia", destination: URL(string: "https://github.com/NTIA/itm")!)
                    Link("Mapzen · DEM y atribuciones", destination: URL(string: "https://github.com/tilezen/joerd/blob/master/docs/attribution.md")!)
                }.font(.caption)
                Text("DEM global · Mapzen, USGS SRTM/GMTED y NOAA ETOPO1; otras atribuciones regionales en el enlace.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
        .onAppear { store.seedTerrainCoordinates(origin: defaultOrigin, destination: defaultDestination) }
    }

    private var endpointFields: some View {
        HStack(alignment: .top, spacing: 16) {
            endpointEditor(title: "Origen · transmisor TX", latitude: $store.terrainOriginLatitude,
                           longitude: $store.terrainOriginLongitude, height: $store.txHeight)
            endpointEditor(title: "Destino · receptor RX", latitude: $store.terrainTargetLatitude,
                           longitude: $store.terrainTargetLongitude, height: $store.rxHeight)
        }
    }

    private func endpointEditor(title: String, latitude: Binding<String>, longitude: Binding<String>, height: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppLocalization.text(title)).font(.headline)
            HStack(spacing: 10) {
                field("Latitud · °", text: latitude, hint: "−33,45", width: 140)
                field("Longitud · °", text: longitude, hint: "−70,67", width: 140)
            }
            field("Altura antena · m AGL", text: height, hint: "10", width: 150)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, text: Binding<String>, hint: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text(title)).font(.caption).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }.frame(width: width)
    }
}
