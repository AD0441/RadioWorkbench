import MapKit
import SwiftUI
import RadioCore

struct RadioActivityMapPanel: View {
    let report: HFPropagationReport?
    let pskSpots: [PSKReceptionSpot]
    let rbnSpots: [RBNSpot]

    private var receiverPoints: [(String, RadioLocation)] {
        Dictionary(pskSpots.compactMap { spot -> (String, RadioLocation)? in
            guard !spot.receiverLocator.isEmpty, let location = Maidenhead.center(spot.receiverLocator) else { return nil }
            return (spot.receiverLocator, location)
        }, uniquingKeysWith: { first, _ in first }).map { ($0.key, $0.value) }
    }
    private var senderPoints: [(String, RadioLocation)] {
        Dictionary(pskSpots.compactMap { spot -> (String, RadioLocation)? in
            guard let locator = spot.senderLocator, let location = Maidenhead.center(locator) else { return nil }
            return (locator, location)
        }, uniquingKeysWith: { first, _ in first }).map { ($0.key, $0.value) }
    }
    private var pskPaths: [[CLLocationCoordinate2D]] {
        pskSpots.prefix(120).compactMap { spot in
            guard let senderGrid = spot.senderLocator,
                  let sender = Maidenhead.center(senderGrid),
                  let receiver = Maidenhead.center(spot.receiverLocator) else { return nil }
            return [coordinate(sender), coordinate(receiver)]
        }
    }
    private var recentRBN: [RBNSpot] {
        let cutoff = Date().addingTimeInterval(-3600)
        return rbnSpots.filter { $0.receivedAt >= cutoff }
    }

    var body: some View {
        GroupBox("Mapa · enlaces observados y ruta del modelo") {
            VStack(alignment: .leading, spacing: 8) {
                Map(initialPosition: .automatic) {
                    if let report {
                        MapPolyline(coordinates: [coordinate(report.input.origin), coordinate(report.input.target)])
                            .stroke(.blue, lineWidth: 3)
                        Annotation("Origen del modelo", coordinate: coordinate(report.input.origin), anchor: .bottom) {
                            Label("Modelo TX", systemImage: "antenna.radiowaves.left.and.right").font(.caption2).padding(4).background(.regularMaterial, in: Capsule())
                        }
                        Annotation("Destino del modelo", coordinate: coordinate(report.input.target), anchor: .bottom) {
                            Label("Modelo RX", systemImage: "dot.radiowaves.left.and.right").font(.caption2).padding(4).background(.regularMaterial, in: Capsule())
                        }
                    }
                    ForEach(Array(pskPaths.enumerated()), id: \.offset) { _, path in
                        MapPolyline(coordinates: path).stroke(.green.opacity(0.65), lineWidth: 2)
                    }
                    ForEach(senderPoints, id: \.0) { grid, location in
                        Marker("Emisor PSK · \(grid)", coordinate: coordinate(location)).tint(.green)
                    }
                    ForEach(receiverPoints, id: \.0) { grid, location in
                        Marker("Receptor PSK · \(grid)", coordinate: coordinate(location)).tint(.orange)
                    }
                }
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 14) {
                    Label("Ruta del cálculo HF", systemImage: "line.diagonal").foregroundStyle(.blue)
                    Label("Recepciones PSK Reporter", systemImage: "point.3.connected.trianglepath.dotted").foregroundStyle(.green)
                    Label("Celdas de receptor", systemImage: "mappin.and.ellipse").foregroundStyle(.orange)
                    Spacer()
                }.font(.caption)
                if recentRBN.isEmpty {
                    Text("RBN: conecta el flujo para ver el volumen de actividad escuchada. El feed entrega frecuencia y skimmer, sin coordenadas de cada spot; esos registros no se dibujan como puntos geográficos.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    let counts = Dictionary(grouping: recentRBN.compactMap { spot -> (String, RBNSpot)? in
                        guard let band = spot.band else { return nil }; return (band, spot)
                    }, by: \.0).mapValues(\.count)
                    HStack {
                        Text("RBN · actividad global recibida en la última hora:").font(.caption.weight(.medium))
                        ForEach(counts.keys.sorted(), id: \.self) { band in
                            Text("\(band) · \(counts[band] ?? 0)").font(.caption.monospacedDigit())
                        }
                    }
                    Text("Los conteos RBN resumen spots del flujo global y no ubican los skimmers; el mapa traza solo cuadrículas que PSK Reporter publica y el trayecto del cálculo seleccionado.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if report == nil {
                    Text("Calcula primero un enlace HF para dibujar su ruta. Las líneas verdes requieren que PSK Reporter incluya locator del emisor y del receptor.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(7)
        }
    }

    private func coordinate(_ location: RadioLocation) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }
}
