import SwiftUI
import MapKit
import RadioCore

struct SatellitePassMapPanel: View {
    let pass: SatellitePass
    let track: [SatelliteTrackSample]
    let observer: RadioLocation
    @ViewState private var camera: MapCameraPosition = .automatic
    var body: some View {
        GroupBox("Pase seleccionado · mapa y dirección de antena") {
            VStack(alignment: .leading, spacing: 8) {
                Text(pass.aos.formatted(date: .abbreviated, time: .shortened) + " → " + pass.los.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                HStack(alignment: .top, spacing: 12) {
                    Map(position: $camera) {
                        ForEach(Array(SatellitePassPredictor.segments(track).enumerated()), id: \.offset) { _, segment in
                            MapPolyline(coordinates: segment.map { coordinate($0.position) }).stroke(.orange, lineWidth: 3)
                        }
                        Marker("Observador", systemImage: "antenna.radiowaves.left.and.right", coordinate: .init(latitude: observer.latitude, longitude: observer.longitude)).tint(.blue)
                        if let first = track.first { Marker("AOS", coordinate: coordinate(first.position)).tint(.green) }
                        if let last = track.last { Marker("LOS", coordinate: coordinate(last.position)).tint(.red) }
                        if let maximum = track.min(by: { abs($0.date.timeIntervalSince(pass.maximumAt)) < abs($1.date.timeIntervalSince(pass.maximumAt)) }) {
                            Marker("Máximo", coordinate: coordinate(maximum.position)).tint(.orange)
                        }
                    }.frame(minWidth: 300, maxWidth: .infinity).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8))
                    SatelliteSkyPlot(track: track).frame(width: 220, height: 240)
                }
                if let first = track.first, let last = track.last {
                    Text("AOS azimut \(first.observation.azimuthDegrees, specifier: "%.0f")° · LOS \(last.observation.azimuthDegrees, specifier: "%.0f")° · máximo \(pass.maximumElevation, specifier: "%.1f")°")
                        .font(.caption.monospacedDigit())
                }
                Text("El mapa muestra la proyección del satélite sobre la Tierra durante el pase; el gráfico polar muestra azimut y elevación desde tu ubicación. Ambos usan Kepler + J2 aproximado y no indican cobertura RF confirmada.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(7)
        }
        .onAppear { fit() }.onChange(of: pass.id) { _, _ in fit() }
    }
    private func coordinate(_ p: SatellitePosition) -> CLLocationCoordinate2D { .init(latitude: p.latitude, longitude: p.longitude) }
    private func fit() {
        let distance = track.compactMap { RadioLocation(latitude: $0.position.latitude, longitude: $0.position.longitude) }
            .map { observer.distance(to: $0) }.max() ?? 1_000
        let extent = min(16_000_000, max(500_000, distance * 2_500))
        camera = .region(MKCoordinateRegion(center: .init(latitude: observer.latitude, longitude: observer.longitude),
            latitudinalMeters: extent, longitudinalMeters: extent))
    }
}

private struct SatelliteSkyPlot: View {
    let track: [SatelliteTrackSample]
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2), radius = min(size.width, size.height) / 2 - 23
            for fraction in [1.0, 2.0 / 3, 1.0 / 3] {
                let r = radius * fraction
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            }
            for (label, x, y) in [("N", center.x, center.y - radius - 12), ("E", center.x + radius + 12, center.y), ("S", center.x, center.y + radius + 12), ("O", center.x - radius - 12, center.y)] {
                context.draw(Text(label).font(.caption), at: CGPoint(x: x, y: y))
            }
            func point(_ sample: SatelliteTrackSample) -> CGPoint {
                let r = radius * (90 - min(90, max(0, sample.observation.elevationDegrees))) / 90
                let a = sample.observation.azimuthDegrees * .pi / 180
                return CGPoint(x: center.x + r * sin(a), y: center.y - r * cos(a))
            }
            var path = Path()
            for (index, sample) in track.enumerated() { if index == 0 { path.move(to: point(sample)) } else { path.addLine(to: point(sample)) } }
            context.stroke(path, with: .color(.orange), lineWidth: 2)
            for (sample, color) in [(track.first, Color.green), (track.last, Color.red)] {
                if let sample { let p = point(sample); context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(color)) }
            }
            context.draw(Text("Centro 90° · borde 0°").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: center.x, y: size.height - 5))
        }
        .accessibilityLabel("Trayectoria de azimut y elevación del pase; norte arriba, este a la derecha")
    }
}
