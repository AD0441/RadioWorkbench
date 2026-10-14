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
                endpointFields

                HStack(spacing: 12) {
                    Button { store.copyLocationToTerrainOrigin(defaultOrigin) } label: {
                        Label("Copiar ubicación guardada al origen", systemImage: "location")
                    }.disabled(defaultOrigin == nil)
                    Button { store.copyHFEndpointToTerrainTarget() } label: {
                        Label("Copiar destino del planificador HF", systemImage: "arrow.down.to.line")
                    }.disabled(defaultDestination == nil)
                    Spacer()
                    if let km = store.terrainHorizon {
                        Label("Radiohorizonte ideal: \(km, specifier: "%.1f") km", systemImage: "circle.dashed")
                            .font(.callout.monospacedDigit())
                    }
                }

                TerrainLinkMapPanel(store: store)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 12) {
                    field("Frecuencia · MHz", text: $store.terrainFrequencyMHz, hint: "144,39", width: 140)
                    field("Potencia TX · W", text: $store.terrainWatts, hint: "10", width: 130)
                    field("Ganancia TX · dBi", text: $store.terrainTxGain, hint: "0", width: 140)
                    field("Ganancia RX · dBi", text: $store.terrainRxGain, hint: "0", width: 140)
                    field("Umbral RX · dBm", text: $store.terrainSensitivityDBm, hint: "−110", width: 140)
                    Picker("Clima ITM", selection: $store.terrainClimate) {
                        ForEach(ITMClimate.allCases) { climate in Text(climate.title).tag(climate) }
                    }.frame(minWidth: 200)
                    Picker("Polarización", selection: $store.terrainVerticalPolarization) {
                        Text("Vertical").tag(true); Text("Horizontal").tag(false)
                    }.frame(width: 145)
                    Link("NTIA ITM / Longley–Rice", destination: URL(string: "https://github.com/NTIA/itm")!)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await store.calculateTerrain() }
                    } label: {
                        if store.terrainBusy { ProgressView().controlSize(.small) }
                        else { Label("Calcular relieve y enlace", systemImage: "mountain.2") }
                    }.buttonStyle(.borderedProminent).disabled(store.terrainBusy)
                    Text(store.terrainStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    field("Radio máximo · km", text: $store.terrainCoverageMaximumKm, hint: "100", width: 145)
                    Button {
                        Task { await store.calculateTerrainCoverage() }
                    } label: {
                        if store.terrainCoverageBusy { ProgressView().controlSize(.small) }
                        else { Label("Calcular zona orientativa", systemImage: "map") }
                    }.buttonStyle(.bordered).disabled(store.terrainCoverageBusy || store.terrainBusy)
                    if store.terrainCoverageBusy {
                        ProgressView(value: Double(store.terrainCoverageCompletedBearings), total: Double(TerrainCoverageGeometry.bearingCount))
                            .frame(width: 120)
                    }
                    Text(store.terrainCoverageStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("La zona evalúa 32 rumbos, perfiles de relieve cada ~500 m y alcances cada 5 km con NTIA ITM. Suma elevación del terreno y AGL en los extremos y estima difracción sobre crestas. Radio: 20–200 km.")
                    .font(.caption2).foregroundStyle(.secondary)

                if let result = store.terrainResult {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 8) {
                        Label("Pérdida ITM: \(result.basicTransmissionLossDB, specifier: "%.1f") dB", systemImage: "arrow.left.arrow.right")
                        Label("Potencia en RX: \(result.receivedPowerDBm, specifier: "%.1f") dBm", systemImage: "waveform.path")
                        if let marginDB {
                            Label("Margen frente al umbral: \(marginDB >= 0 ? "+" : "")\(marginDB, specifier: "%.1f") dB", systemImage: marginDB >= 0 ? "checkmark.radiowaves.left.and.right" : "exclamationmark.radiowaves.left.and.right")
                        }
                        Label(result.propagationMode, systemImage: "mountain.2")
                        Text("Irregularidad del terreno: \(result.terrainIrregularityMeters, specifier: "%.0f") m · avisos ITM: \(result.warningFlags)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.font(.callout).textSelection(.enabled)
                }

                Text("Las alturas TX/RX se ingresan sobre el suelo (AGL); NTIA ITM las combina con las elevaciones del terreno AMSL y modela difracción en montañas. El corte muestra el terreno y la línea directa: una obstrucción no significa silencio total. La zona radial sigue siendo una aproximación, no una probabilidad ni garantía; no incluye edificios, vegetación, patrón de antena, pérdidas de cable, interferencia, ductos o esporádica E. Open-Meteo consulta Copernicus GLO-90 solo al pulsar Calcular.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("Open-Meteo · elevación y licencia", destination: URL(string: "https://open-meteo.com/en/docs/elevation-api")!)
                    Link("NTIA · código y licencia", destination: URL(string: "https://github.com/NTIA/itm")!)
                    Text("Relieve DEM: Open-Meteo · Copernicus GLO-90").foregroundStyle(.secondary)
                }.font(.caption)
            }.padding(8)
        }
        .disabled(store.terrainBusy || store.terrainCoverageBusy)
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
            Text(title).font(.headline)
            HStack(spacing: 10) {
                field("Latitud · °", text: latitude, hint: "−33,45", width: 140)
                field("Longitud · °", text: longitude, hint: "−70,67", width: 140)
                field("Altura antena · m AGL", text: height, hint: "10", width: 150)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, text: Binding<String>, hint: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder).accessibilityLabel(title)
        }.frame(width: width)
    }
}
