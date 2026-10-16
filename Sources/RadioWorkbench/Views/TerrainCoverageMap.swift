import SwiftUI
@preconcurrency import MapKit
import RadioCore

/// Only the map crosses into AppKit, to display a dense, georeferenced raster without thousands of view polygons.
struct TerrainCoverageMap: NSViewRepresentable {
    let origin: RadioLocation?
    let target: RadioLocation?
    let report: TerrainCoverageReport?
    let frequencyMHz: Double?
    let showShadows: Bool
    let idealHorizonKm: Double?
    let relief: Bool
    let onTap: @MainActor (RadioLocation) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        map.addGestureRecognizer(click)
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(map)
    }
    static func dismantleNSView(_ view: MKMapView, coordinator: Coordinator) { view.delegate = nil }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TerrainCoverageMap
        private struct ContentID: Equatable {
            let origin: RadioLocation?
            let target: RadioLocation?
            let report: UUID?
            let frequency: Double?
            let shadows: Bool
            let horizon: Double?
        }
        private var signature: ContentID?
        private var lastOrigin: RadioLocation?
        private var lastTarget: RadioLocation?
        private var lastReportID: UUID?
        private var lastRelief: Bool?
        init(_ parent: TerrainCoverageMap) { self.parent = parent }
        func update(_ map: MKMapView) {
            let key = ContentID(origin: parent.origin, target: parent.target, report: parent.report?.id,
                frequency: parent.frequencyMHz, shadows: parent.showShadows, horizon: parent.idealHorizonKm)
            if signature != key {
                signature = key
                map.removeOverlays(map.overlays)
                map.removeAnnotations(map.annotations)
                if let report = parent.report, let overlay = TerrainCoverageOverlay(report: report, showShadows: parent.showShadows) {
                    map.addOverlay(overlay, level: .aboveRoads)
                }
                if let origin = parent.origin {
                    addMarker(map, title: "Origen · TX", location: origin)
                    if let radius = parent.idealHorizonKm { map.addOverlay(MKCircle(center: coordinate(origin), radius: radius * 1_000)) }
                }
                if let target = parent.target { addMarker(map, title: "Destino · RX", location: target) }
                if let origin = parent.origin, let target = parent.target {
                    map.addOverlay(MKGeodesicPolyline(coordinates: [coordinate(origin), coordinate(target)], count: 2), level: .aboveLabels)
                    if let frequency = parent.frequencyMHz {
                        let corridor = TerrainLinkGeometry.firstFresnelCorridor(from: origin, to: target, frequencyMHz: frequency).map(coordinate)
                        if !corridor.isEmpty { map.addOverlay(MKPolygon(coordinates: corridor, count: corridor.count), level: .aboveRoads) }
                    }
                }
            }
            if lastOrigin != parent.origin || lastReportID != parent.report?.id || (parent.report == nil && lastTarget != parent.target) {
                if let report = parent.report {
                    let world = MKMapSize.world.width
                    let rect = MKMapRect(x: report.layout.minX * world, y: report.layout.minY * world,
                                         width: report.layout.span * world, height: report.layout.span * world)
                    map.setVisibleMapRect(rect, edgePadding: NSEdgeInsets(top: 25, left: 25, bottom: 25, right: 25), animated: false)
                } else if let origin = parent.origin {
                    if let target = parent.target,
                       let center = origin.destination(km: origin.distance(to: target) / 2, bearing: origin.bearing(to: target)) {
                        let extent = max(12_000, origin.distance(to: target) * 1_200)
                        map.setRegion(MKCoordinateRegion(center: coordinate(center), latitudinalMeters: extent, longitudinalMeters: extent), animated: false)
                    } else {
                        map.setRegion(MKCoordinateRegion(center: coordinate(origin), latitudinalMeters: 80_000, longitudinalMeters: 80_000), animated: false)
                    }
                }
                lastOrigin = parent.origin; lastTarget = parent.target; lastReportID = parent.report?.id
                lastRelief = nil
            }
            if lastRelief != parent.relief {
                let camera = map.camera
                camera.pitch = parent.relief ? 50 : 0
                map.setCamera(camera, animated: false)
                lastRelief = parent.relief
            }
        }
        @objc func clicked(_ gesture: NSClickGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            if let point = RadioLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) { parent.onTap(point) }
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.markerTintColor = annotation.title == "Origen · TX" ? .systemBlue : .systemOrange
            view.canShowCallout = true
            return view
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let raster = overlay as? TerrainCoverageOverlay { return TerrainCoverageRenderer(overlay: raster) }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.35)
                renderer.lineWidth = 1; renderer.lineDashPattern = [5, 5]
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = .systemOrange; renderer.lineWidth = 3
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = NSColor.systemCyan.withAlphaComponent(0.2)
                renderer.strokeColor = .systemCyan; renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        private func addMarker(_ map: MKMapView, title: String, location: RadioLocation) {
            let annotation = MKPointAnnotation(); annotation.title = title; annotation.coordinate = coordinate(location)
            map.addAnnotation(annotation)
        }
        private func coordinate(_ location: RadioLocation) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        }
    }
}

final class TerrainCoverageOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: CGImage
    init?(report: TerrainCoverageReport, showShadows: Bool) {
        let size = report.layout.side
        let bytes = Data(report.rgba(showShadows: showShadows))
        guard let provider = CGDataProvider(data: bytes as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        self.image = image
        coordinate = CLLocationCoordinate2D(latitude: report.layout.origin.latitude, longitude: report.layout.origin.longitude)
        let world = MKMapSize.world.width
        boundingMapRect = MKMapRect(x: report.layout.minX * world, y: report.layout.minY * world,
                                   width: report.layout.span * world, height: report.layout.span * world)
    }
}

final class TerrainCoverageRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let raster = overlay as? TerrainCoverageOverlay else { return }
        let intersection = mapRect.intersection(raster.boundingMapRect)
        guard !intersection.isNull && !intersection.isEmpty else { return }
        let rect = rect(for: raster.boundingMapRect)
        context.saveGState()
        context.clip(to: self.rect(for: intersection))
        context.interpolationQuality = .none
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(raster.image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
