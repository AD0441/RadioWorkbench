import SwiftUI
import MapKit
import RadioCore

struct RepeaterMapPanel: View {
    @Bindable var store: RadioConsultationStore
    let observer: RadioLocation?
    @ViewState private var camera: MapCameraPosition = .automatic
    @ViewState private var placing = false
    private var selection: Binding<String?> {
        Binding(get: { store.selectedRepeaterID }, set: { id in
            store.chooseRepeater(store.repeaters.first { $0.id == id })
        })
    }
    private var located: [(VHFRepeater, RadioLocation)] {
        store.filteredRepeaters.compactMap { repeater in
            guard let lat = repeater.latitude, let lon = repeater.longitude,
                let location = RadioLocation(latitude: lat, longitude: lon) else { return nil }
            return (repeater, location)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MapReader { proxy in
                Map(position: $camera, selection: selection) {
                    ForEach(located.map(\.0)) { repeater in
                        if repeater.id != store.selectedRepeaterID, let lat = repeater.latitude, let lon = repeater.longitude {
                            Marker(repeater.id, systemImage: "antenna.radiowaves.left.and.right",
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)).tint(.blue).tag(repeater.id)
                        }
                    }
                    if let repeater = store.selectedRepeater, let location = store.makeSelectedRepeaterLocation() {
                        Marker(repeater.id, systemImage: "antenna.radiowaves.left.and.right", coordinate: coordinate(location))
                            .tint(.orange).tag(repeater.id)
                    }
                    if let observer { Annotation("Tu ubicación", coordinate: coordinate(observer)) { Image(systemName: "house.fill").foregroundStyle(.green).padding(5).background(.background, in: Circle()) } }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onTapGesture { point in
                    guard placing, store.selectedRepeater != nil, let value = proxy.convert(point, from: .local),
                        let location = RadioLocation(latitude: value.latitude, longitude: value.longitude) else { return }
                    store.repeaterLatitude = RadioConsultationStore.coordinateText(location.latitude)
                    store.repeaterLongitude = RadioConsultationStore.coordinateText(location.longitude)
                }
            }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Toggle("Ubicar con clic", isOn: $placing).disabled(store.selectedRepeater == nil)
                Button("Centrar sitio") { center() }
            }.font(.caption)
            Text("\(located.count) sitios con coordenadas publicadas entre \(store.filteredRepeaters.count) resultados. Naranja: sitio seleccionado. Activa Ubicar con clic para elegir un punto manual que se usará en ITM.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { center() }
        .onChange(of: store.selectedRepeaterID) { _, _ in placing = false; center() }
        .onChange(of: store.repeaters.count) { _, _ in if store.selectedRepeaterID == nil { center() } }
    }
    private func center() {
        let point = store.makeSelectedRepeaterLocation() ?? observer ?? located.first?.1
        if let point { camera = .region(MKCoordinateRegion(center: coordinate(point), latitudinalMeters: 60_000, longitudinalMeters: 60_000)) }
        else { camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -35.5, longitude: -71.5), span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 18))) }
    }
    private func coordinate(_ location: RadioLocation) -> CLLocationCoordinate2D { .init(latitude: location.latitude, longitude: location.longitude) }
}
