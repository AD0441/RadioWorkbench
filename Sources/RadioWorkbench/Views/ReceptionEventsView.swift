import MapKit
import SwiftUI
import RadioCore

struct ReceptionEventsView: View {
    @Bindable var store: ReceptionEventStore
    var showMap = true
    @ViewState private var camera: MapCameraPosition = .automatic
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(showMap ? "Mapa de recepciones" : "Eventos de otros decodificadores").font(.largeTitle.weight(.semibold))
                Text(showMap ? "Posiciones recibidas, procedencia y trazas por estación. Los puntos de archivos no confirman una recepción en vivo." : "Importa un archivo de eventos con su fuente, protocolo, fecha y resultado de integridad. Las posiciones válidas aparecen también en el mapa.")
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("Fuente", selection: $store.sourceFilter) {
                        Text("Todas").tag("Todas")
                        ForEach(store.sources, id: \.self) { Text($0).tag($0) }
                    }.frame(maxWidth: 400)
                    Button("Importar eventos…") { store.importFile() }.disabled(store.busy)
                    Button("Exportar visibles…") { store.export() }.disabled(store.visible.isEmpty || store.busy)
                    if store.busy { ProgressView().controlSize(.small) }
                }
                Text(store.status).font(.caption).foregroundStyle(.secondary)
                if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if showMap {
                    TimelineView(.periodic(from: Date(), by: 30)) { context in
                        VStack(alignment: .leading) {
                            Map(position: $camera) {
                                ForEach(Array(ReceptionTrace.segments(Array(store.visible.prefix(1000))).enumerated()), id: \.offset) { _, segment in
                                    MapPolyline(coordinates: segment.map { CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) })
                                        .stroke(.blue.opacity(0.5), lineWidth: 2)
                                }
                                ForEach(Array(store.latestPositions.prefix(300))) { event in
                                    Annotation(event.entityID, coordinate: CLLocationCoordinate2D(latitude: event.latitude!, longitude: event.longitude!)) {
                                        Button { store.selectedID = event.id } label: {
                                            VStack(spacing: 2) {
                                                Image(systemName: event.protocolName == "ACARS" ? "airplane.circle.fill" : "mappin.circle.fill").font(.title2)
                                                Text(event.entityID).font(.caption2)
                                            }.padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                        }.buttonStyle(.plain).tint(age(event, at: context.date) > 1800 ? .gray : .blue)
                                    }
                                }
                            }.mapStyle(.standard(elevation: .realistic)).frame(height: 400).clipShape(RoundedRectangle(cornerRadius: 10))
                            HStack {
                                Button("Encuadrar posiciones") { camera = .automatic }
                                Text("Hasta 300 posiciones · trazas de los últimos 1.000 eventos · gris tras 30 min.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let event = store.events.first(where: { $0.id == store.selectedID }) {
                    GroupBox("\(event.protocolName) · \(event.entityID)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fuente: \(event.source) · \(sourceName(event.sourceKind))")
                            Text("Recepción según la fuente: \(event.receivedAt.formatted())")
                            if let imported = event.importedAt { Text("Importado en este Mac: \(imported.formatted())") }
                            Text("Hora de observación/captura: \(event.observedAt?.formatted() ?? "no disponible; no se deduce de la importación")")
                            if let location = event.location { Text("\(location.latitude.formatted()), \(location.longitude.formatted())") }
                            Text(event.integrity).foregroundStyle(.secondary)
                            Text(event.message).textSelection(.enabled)
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
                Table(Array(store.visible.prefix(200)), selection: $store.selectedID) {
                    TableColumn("Protocolo", value: \.protocolName).width(80)
                    TableColumn("Estación", value: \.entityID).width(110)
                    TableColumn("Fuente", value: \.source)
                    TableColumn("Recibido") { Text($0.receivedAt.formatted(date: .abbreviated, time: .standard)) }
                    TableColumn("Posición") { Text($0.location == nil ? "Sin coordenadas" : "Disponible") }
                }.frame(height: 250)
                Text("Máximo 5.000 eventos en memoria y 200 filas visibles. APRS-IS conserva su conexión optativa en Consultas; el mapa no inicia una consulta. ACARS aporta posiciones ADS-C ya decodificadas. El formato externo v1 se documenta en el proyecto; importar no ejecuta órdenes ni verifica por sí solo un CRC declarado por otro programa.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func age(_ event: ReceptionEvent, at date: Date) -> TimeInterval { max(0, date.timeIntervalSince(event.observedAt ?? event.receivedAt)) }
    private func sourceName(_ source: ReceptionEventSource) -> String {
        switch source {
        case .audioFile: "archivo de audio"
        case .audioLive: "entrada de audio en vivo"
        case .networkAudio: "audio de red"
        case .internet: "Internet"
        case .imported: "adaptador externo; procedencia declarada"
        }
    }
}
