import MapKit
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

    private var route: [CLLocationCoordinate2D] {
        guard let origin = store.terrainOrigin, let destination = store.terrainTarget else { return [] }
        return [coordinate(origin), coordinate(destination)]
    }
    private var corridor: [CLLocationCoordinate2D] {
        guard let origin = store.terrainOrigin, let destination = store.terrainTarget,
              let frequency = store.number(store.terrainFrequencyMHz) else { return [] }
        return TerrainLinkGeometry.firstFresnelCorridor(from: origin, to: destination, frequencyMHz: frequency).map(coordinate)
    }
    private var lineOfSight: TerrainLineOfSightResult? {
        guard let profile = currentProfile,
              let txHeight = store.number(store.txHeight), let rxHeight = store.number(store.rxHeight) else { return nil }
        return TerrainLineOfSight.evaluate(profile: profile, txHeightAGLMeters: txHeight, rxHeightAGLMeters: rxHeight)
    }
    private var initialMapPosition: MapCameraPosition {
        guard store.terrainMapShowingRelief, let origin = store.terrainOrigin else { return .automatic }
        let reach = store.terrainCoverageReachByBearing.max() ?? 0
        let linkDistance = store.terrainTarget.map { origin.distance(to: $0) } ?? 0
        let selectedMaximum = store.number(store.terrainCoverageMaximumKm) ?? 0
        let spanKm = max(max(max(reach, linkDistance / 2), min(selectedMaximum, 100)), 5)
        return .camera(MapCamera(centerCoordinate: coordinate(origin), distance: spanKm * 3_000, heading: 0, pitch: 55))
    }

    var body: some View {
        GroupBox("Apple Maps con relieve · zona orientativa") {
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
                MapReader { proxy in
                    Map(initialPosition: initialMapPosition) {
                        if let origin = store.terrainOrigin, let horizon = store.terrainHorizon {
                            MapCircle(center: coordinate(origin), radius: horizon * 1_000)
                                .stroke(.blue.opacity(0.3), lineWidth: 1)
                        }
                        if store.terrainCoverageBoundary.count >= 4 {
                            MapPolygon(coordinates: store.terrainCoverageBoundary.map(coordinate))
                                .foregroundStyle(.purple.opacity(0.16))
                                .stroke(.purple.opacity(0.55), lineWidth: 1.5)
                        }
                        if corridor.count >= 8 {
                            MapPolygon(coordinates: corridor)
                                .foregroundStyle(.cyan.opacity(0.2))
                                .stroke(.cyan.opacity(0.6), lineWidth: 1)
                        }
                        if route.count == 2 {
                            MapPolyline(coordinates: route).stroke(.orange, lineWidth: 3)
                        }
                        if let origin = store.terrainOrigin {
                            Marker("Origen · TX", coordinate: coordinate(origin)).tint(.blue)
                        }
                        if let destination = store.terrainTarget {
                            Marker("Destino · RX", coordinate: coordinate(destination)).tint(.orange)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .id(store.terrainMapShowingRelief)
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        guard let point = proxy.convert(value.location, from: .local),
                              let location = RadioLocation(latitude: point.latitude, longitude: point.longitude) else { return }
                        if store.terrainMapSelection == "origin" { store.setTerrainOrigin(location) }
                        else { store.setTerrainTarget(location) }
                    })
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 16) {
                    Label("Origen TX", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.blue)
                    Label("Destino RX", systemImage: "mappin.and.ellipse").foregroundStyle(.orange)
                    Label("Envolvente ITM al umbral RX", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.purple)
                    Label("Corredor Fresnel 1 · 60%", systemImage: "point.3.connected.trianglepath.dotted").foregroundStyle(.cyan)
                    Label("Radiohorizonte geométrico de referencia", systemImage: "circle.dashed").foregroundStyle(.blue)
                }.font(.caption)

                if let profile = currentProfile {
                    if let lineOfSight { terrainCrossSection(profile, lineOfSight: lineOfSight) }
                    endpointElevations(profile)
                } else if let ground = store.terrainCoverageOriginElevationMeters,
                          let height = store.number(store.txHeight) {
                    Text("TX: terreno \(ground, specifier: "%.0f") m + AGL \(height, specifier: "%.0f") m = \(ground + height, specifier: "%.0f") m s. n. m. · usado en los perfiles ITM radiales")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("El relieve del mapa es orientativo. Al calcular, el perfil Copernicus GLO-90 aporta las elevaciones a lo largo del trayecto seleccionado.")
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
                    LineMark(x: .value("Distancia", distance), y: .value("Relieve", lineOfSight.apparentTerrainAltitudeAMSL[index]))
                        .foregroundStyle(.brown).interpolationMethod(.linear)
                }
                ForEach(lineOfSight.rayAltitudeAMSL.indices, id: \.self) { index in
                    let distance = profile.distanceKm * Double(index) / Double(profile.points.count - 1)
                    LineMark(x: .value("Distancia", distance), y: .value("Rayo", lineOfSight.rayAltitudeAMSL[index]))
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


    private func coordinate(_ location: RadioLocation) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }
}
