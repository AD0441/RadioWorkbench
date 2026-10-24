import SwiftUI
import MapKit
import Charts
import RadioCore

struct ListeningMapView: View {
    @Bindable var library: ReceptionLibraryStore
    @Bindable var events: ReceptionEventStore
    @ViewState private var layer = "Escuchas anotadas"
    @ViewState private var camera: MapCameraPosition = .automatic
    @ViewState private var filter = ListeningFilter()
    @ViewState private var limitsDates = false
    @ViewState private var from = Calendar.current.startOfDay(for: Date())
    @ViewState private var through = Date()
    @ViewState private var localTime = false
    @ViewState private var selected: UUID?
    @ViewState private var onlyUnlocated = false
    private var visible: [ListeningObservation] {
        var current = filter
        current.from = limitsDates ? from : nil; current.through = limitsDates ? through : nil
        current.timeZone = localTime ? .current : TimeZone(secondsFromGMT: 0)!
        return library.observations.filter { current.includes($0) && (!onlyUnlocated || $0.transmitter == nil || $0.receivingStation.location == nil) }
    }
    private var positioned: [ListeningObservation] { visible.filter { $0.transmitter != nil && $0.receivingStation.location != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Capa del mapa", selection: $layer) {
                Text("Escuchas anotadas").tag("Escuchas anotadas")
                Text("Posiciones APRS / ACARS / externas").tag("Eventos")
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.top, 12)
            if layer == "Eventos" { ReceptionEventsView(store: events) }
            else { observations }
        }.task { library.load() }
    }
    private var observations: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alcance observado de recepción").font(.largeTitle.weight(.semibold))
                Text("Trayectos TX → RX de tu biblioteca. Cada ficha conserva la posición, receptor y antena del momento; WebSDR se filtra aparte.").foregroundStyle(.secondary)
                filters
                Text("\(visible.count) intentos · \(visible.filter { $0.outcome == .heard }.count) escuchados · \(positioned.count) trayectos localizados · \(visible.count - positioned.count) pendientes de posición.").font(.caption)
                Map(position: $camera) {
                    ForEach(Array(positioned.prefix(500))) { item in
                        let tx = item.transmitter!, rx = item.receivingStation.location!
                        ForEach(Array(item.mapSegments.enumerated()), id: \.offset) { _, segment in
                            MapPolyline(coordinates: segment.map(coordinate)).stroke(color(item).opacity(0.65), lineWidth: item.outcome == .heard ? 2 : 1)
                        }
                        Annotation(item.stationName, coordinate: coordinate(tx)) {
                            Button { selected = item.id } label: {
                                Image(systemName: item.outcome == .heard ? "antenna.radiowaves.left.and.right.circle.fill" : "questionmark.circle.fill")
                                    .font(.title2).foregroundStyle(color(item)).padding(3).background(.regularMaterial, in: Circle())
                            }.buttonStyle(.plain).help("\(item.stationName) · \(item.outcome.title)")
                        }
                        Annotation("RX · \(item.receivingStation.antenna)", coordinate: coordinate(rx)) {
                            Image(systemName: "ear.fill").foregroundStyle(.orange).padding(4).background(.regularMaterial, in: Circle())
                        }
                    }
                }.mapStyle(.standard(elevation: .realistic)).frame(height: 410).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button("Encuadrar trayectos") { camera = .automatic }
                    Text("Verde: escuchada · gris: no escuchada · naranja: dudosa. Hasta 500 trayectos visibles.").font(.caption).foregroundStyle(.secondary)
                }
                if let item = visible.first(where: { $0.id == selected }) { detail(item) }
                summaries
                Text("El alcance observado depende de lo que intentaste escuchar, fecha, equipo y condiciones. No describe cobertura continua ni el patrón de radiación. Un intento fallido tampoco confirma que la emisora estuviera al aire.").font(.caption).foregroundStyle(.secondary)
                Table(Array(visible.prefix(500)), selection: $selected) {
                    TableColumn("Emisora", value: \.stationName)
                    TableColumn("Resultado") { Text($0.outcome.title) }
                    TableColumn(localTime ? "Fecha local" : "Fecha UTC") { Text(dateText($0.observedAt)) }
                    TableColumn("Antena") { Text($0.receivingStation.antenna.isEmpty ? "Sin anotar" : $0.receivingStation.antenna) }
                    TableColumn("km") { Text($0.distanceKm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "Sin posición") }
                }.frame(height: 250)
            }.padding(20)
        }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Limitar fechas", isOn: $limitsDates)
                DatePicker("Desde", selection: $from).disabled(!limitsDates)
                DatePicker("Hasta", selection: $through).disabled(!limitsDates)
                Toggle("Hora local", isOn: $localTime)
            }
            HStack {
                Picker("Hora inicial", selection: $filter.firstHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                Picker("Hora final", selection: $filter.lastHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                Picker("Origen", selection: $filter.origin) {
                    Text("Todos").tag(ListeningOrigin?.none)
                    ForEach(ListeningOrigin.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
            }
            HStack {
                optionPicker("Antena", selection: $filter.antenna, values: library.observations.map(\.receivingStation.antenna))
                optionPicker("Banda", selection: $filter.band, values: library.observations.map(\.band))
                Picker("Modo SDR", selection: $filter.modulation) {
                    Text("Todos").tag("Todos")
                    ForEach(Array(Set(library.observations.map(\.modulation))).sorted(), id: \.self) { Text($0) }
                }
            }
            HStack {
                Picker("Evidencia", selection: $filter.evidence) {
                    Text("Todas").tag(ListeningEvidence?.none)
                    ForEach(ListeningEvidence.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Toggle("Solo pendientes de localizar", isOn: $onlyUnlocated)
            }
        }.controlSize(.small)
    }
    private func optionPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Todas").tag("Todas")
            ForEach(Array(Set(values.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0) }
        }
    }
    private func detail(_ item: ListeningObservation) -> some View {
        GroupBox(item.stationName) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(item.outcome.title) · \(dateText(item.observedAt)) · \(item.frequencyHz / 1000, specifier: "%.2f") kHz · \(item.receivingStation.origin.title)")
                if let distance = item.distanceKm, let bearing = item.bearing { Text("TX → RX: \(distance, specifier: "%.0f") km · rumbo RX → TX: \(bearing, specifier: "%.0f")°") }
                Text("TX: \(item.transmitterName.isEmpty ? "sin sitio confirmado" : item.transmitterName) · \(item.transmitterSource)")
                Text("RX: \(item.receivingStation.receiver) · Antena: \(item.receivingStation.antenna)")
                Text(item.notes).textSelection(.enabled)
                Button("Editar / completar posición") { library.editingObservation = item }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
    private var summaries: some View {
        let observations = visible
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localTime ? .current : TimeZone(secondsFromGMT: 0)!
        let hours = (0..<24).map { hour in (hour, observations.filter { calendar.component(.hour, from: $0.observedAt) == hour }) }
        let localHeard = observations.filter { $0.outcome == .heard && $0.receivingStation.origin == .local && $0.distanceKm != nil }
        let sectors = (0..<8).map { index in localHeard.filter { Int((($0.bearing ?? 0) + 22.5).truncatingRemainder(dividingBy: 360) / 45) == index }.compactMap(\.distanceKm).max() }
        return GroupBox("Historial por hora y rumbo") {
            VStack(alignment: .leading) {
                Chart(hours, id: \.0) { hour, items in
                    BarMark(x: .value("Hora", hour), y: .value("Intentos", items.count)).foregroundStyle(.gray.opacity(0.35))
                    BarMark(x: .value("Hora", hour), y: .value("Escuchadas", items.filter { $0.outcome == .heard }.count)).foregroundStyle(.green)
                        .position(by: .value("Resultado", "Escuchadas"))
                }.chartXAxis { AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21, 23]) }.frame(height: 130)
                Text("Intentos y escuchadas por hora \(localTime ? "local" : "UTC"), acumulados en el intervalo elegido.").font(.caption)
                Text(zip(["N", "NE", "E", "SE", "S", "SO", "O", "NO"], sectors).map { name, distance in
                    "\(name): \(distance.map { String(format: "%.0f km", $0) } ?? "sin datos")"
                }.joined(separator: " · ")).font(.caption).textSelection(.enabled)
                Text("Mayor distancia anotada por rumbo, solo escuchadas con antena local. Selecciona una antena y banda para comparar condiciones equivalentes.").font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }
    private func coordinate(_ value: RadioLocation) -> CLLocationCoordinate2D { .init(latitude: value.latitude, longitude: value.longitude) }
    private func color(_ item: ListeningObservation) -> Color { item.outcome == .heard ? .green : item.outcome == .notHeard ? .gray : .orange }
    private func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: localTime ? .current : TimeZone(secondsFromGMT: 0)!))
    }
}
