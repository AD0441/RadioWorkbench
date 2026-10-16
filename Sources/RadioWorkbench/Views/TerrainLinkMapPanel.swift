import SwiftUI
import Charts
import RadioCore

struct TerrainLinkMapPanel: View {
    @Bindable var store: PropagationStore

    private var currentProfile: TerrainProfile? {
        guard let profile = store.terrainProfile, profile.origin == store.terrainOrigin,
              profile.target == store.terrainTarget else { return nil }
        return profile
    }

    private var lineOfSight: TerrainLineOfSightResult? {
        guard let profile = currentProfile,
              let txHeight = store.number(store.txHeight), let rxHeight = store.number(store.rxHeight) else { return nil }
        return TerrainLineOfSight.evaluate(profile: profile, txHeightAGLMeters: txHeight, rxHeightAGLMeters: rxHeight)
    }
    var body: some View {
        GroupBox("Apple Maps con relieve · cobertura por celda") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center) {
                    Picker("Al pulsar el mapa, cambiar", selection: $store.terrainMapSelection) {
                        Text("Origen · TX").tag("origin")
                        Text("Destino · RX").tag("destination")
                    }.pickerStyle(.segmented).frame(maxWidth: 330)
                    Picker("Vista del mapa", selection: $store.terrainMapShowingRelief) {
                        Text("Plano").tag(false)
                        Text("Relieve 3D").tag(true)
                    }.pickerStyle(.segmented).frame(width: 190)
                    Text("Seleccionado: \(store.terrainMapSelection == "origin" ? "Origen · TX" : "Destino · RX"). Haz clic en el mapa para ubicarlo.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                TerrainCoverageMap(origin: store.terrainOrigin, target: store.terrainTarget,
                    report: store.terrainCoverageReport, frequencyMHz: store.number(store.terrainFrequencyMHz),
                    showShadows: store.terrainCoverageShowShadows,
                    idealHorizonKm: store.terrainMapShowingHorizon ? store.terrainHorizon : nil,
                    relief: store.terrainMapShowingRelief) { location in
                        if store.terrainMapSelection == "origin" { store.setTerrainOrigin(location) }
                        else { store.setTerrainTarget(location) }
                    }
                .allowsHitTesting(!store.terrainBusy && !store.terrainCoverageBusy)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 16) {
                    Label("Origen TX", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.blue)
                    Label("Destino RX", systemImage: "mappin.and.ellipse").foregroundStyle(.orange)
                    Label("Margen ≥10 dB", systemImage: "square.fill").foregroundStyle(.green)
                    Label("Margen 0–10 dB", systemImage: "square.fill").foregroundStyle(.orange)
                    Label("Corredor Fresnel 1 · 60%", systemImage: "point.3.connected.trianglepath.dotted").foregroundStyle(.cyan)
                    if store.terrainCoverageShowShadows {
                        Label("Bajo umbral RX", systemImage: "square.fill").foregroundStyle(.red)
                    }
                }.font(.caption)

                HStack {
                    Toggle("Mostrar celdas bajo umbral", isOn: $store.terrainCoverageShowShadows)
                    Toggle("Referencia de Tierra lisa (AGL)", isOn: $store.terrainMapShowingHorizon)
                }.font(.caption)
                if let coverage = store.terrainCoverageReport, let destination = store.terrainTarget,
                   let cell = coverage.cell(at: destination) {
                    Text("Celda del destino: \(cell.receivedPowerDBm, specifier: "%.1f") dBm · margen \(cell.receivedPowerDBm - coverage.thresholdDBm, specifier: "%.1f") dB · \(cell.propagationMode) · terreno \(cell.groundMeters, specifier: "%.0f") m · avisos \(cell.warningFlags). Resolución \(coverage.layout.spacingMeters, specifier: "%.0f") m; calcula el enlace para el punto exacto.")
                        .font(.caption.monospacedDigit()).textSelection(.enabled)
                    if cell.warningFlags != 0 {
                        Text("Avisos de esta celda: " + TerrainITMWarning.descriptions(flags: cell.warningFlags).joined(separator: "; "))
                            .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }
                if let profile = currentProfile {
                    if let lineOfSight { terrainCrossSection(profile, lineOfSight: lineOfSight) }
                    endpointElevations(profile)
                } else if let ground = store.terrainCoverageOriginElevationMeters,
                          let height = store.number(store.txHeight) {
                    Text("TX: terreno \(ground, specifier: "%.0f") m + AGL \(height, specifier: "%.0f") m = \(ground + height, specifier: "%.0f") m s. n. m. · usado en cada trayecto TX→celda")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("Al calcular la malla, un DEM aporta las elevaciones de cada trayecto TX→celda. El relieve de Apple Maps sirve de contexto y no sustituye esos datos.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(7)
        }
    }

    @ViewBuilder private func endpointElevations(_ profile: TerrainProfile) -> some View {
        let originGround = profile.points.first?.elevationMeters
        let destinationGround = profile.points.last?.elevationMeters
        HStack(spacing: 18) {
            if let ground = originGround, let height = store.number(store.txHeight) {
                let antennaAltitude = profile.antennaAltitudeAMSL(aglMeters: height, atOrigin: true) ?? ground + height
                Text("TX: terreno \(ground, specifier: "%.0f") m + AGL \(height, specifier: "%.0f") m = \(antennaAltitude, specifier: "%.0f") m s. n. m.")
            }
            if let ground = destinationGround, let height = store.number(store.rxHeight) {
                let antennaAltitude = profile.antennaAltitudeAMSL(aglMeters: height, atOrigin: false) ?? ground + height
                Text("RX: terreno \(ground, specifier: "%.0f") m + AGL \(height, specifier: "%.0f") m = \(antennaAltitude, specifier: "%.0f") m s. n. m.")
            }
            Spacer(minLength: 0)
        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }

    private func terrainCrossSection(_ profile: TerrainProfile, lineOfSight: TerrainLineOfSightResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Corte topográfico del enlace").font(.subheadline.weight(.semibold))
                Spacer()
                if lineOfSight.isClear {
                    Label("Línea directa despejada · holgura mínima \(lineOfSight.minimumClearanceMeters, specifier: "%.0f") m", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("Montaña cruza la línea directa · \(abs(lineOfSight.minimumClearanceMeters), specifier: "%.0f") m", systemImage: "mountain.2.fill")
                        .foregroundStyle(.orange)
                }
            }.font(.caption)
            Chart {
                ForEach(profile.points.indices, id: \.self) { index in
                    let distance = profile.distanceKm * Double(index) / Double(profile.points.count - 1)
                    LineMark(x: .value("Distancia", distance), y: .value("Relieve", lineOfSight.apparentTerrainAltitudeAMSL[index]), series: .value("Serie", "Terreno"))
                        .foregroundStyle(.brown).interpolationMethod(.linear)
                }
                ForEach(lineOfSight.rayAltitudeAMSL.indices, id: \.self) { index in
                    let distance = profile.distanceKm * Double(index) / Double(profile.points.count - 1)
                    LineMark(x: .value("Distancia", distance), y: .value("Rayo", lineOfSight.rayAltitudeAMSL[index]), series: .value("Serie", "Rayo"))
                        .foregroundStyle(.cyan).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
                ForEach(lineOfSight.clearanceMeters.indices.filter({ lineOfSight.clearanceMeters[$0] < 0 }), id: \.self) { index in
                    let distance = profile.distanceKm * Double(index) / Double(profile.points.count - 1)
                    PointMark(x: .value("Obstáculo", distance), y: .value("Cresta", lineOfSight.apparentTerrainAltitudeAMSL[index]))
                        .foregroundStyle(.orange).symbolSize(34)
                }
            }
            .chartXAxisLabel("Distancia · km")
            .chartYAxisLabel("Altitud AMSL · m")
            .frame(height: 155)
            HStack(spacing: 14) {
                Label("Terreno + curvatura k=4/3", systemImage: "mountain.2").foregroundStyle(.brown)
                Label("Rayo entre antenas", systemImage: "line.diagonal").foregroundStyle(.cyan)
                Text("NTIA ITM también estima difracción: una cresta obstruye la vista directa, pero no implica silencio total.")
                    .foregroundStyle(.secondary)
            }.font(.caption2)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
