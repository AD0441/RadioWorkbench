import SwiftUI
import RadioCore

struct RadioConsultationsView: View {
    @Bindable var store: RadioConsultationStore
    @Bindable var receiver: ReceiverStore
    @Bindable var guide: BroadcastStore
    @Bindable var propagation: PropagationStore
    @Bindable var aprs: APRSISStore
    @Bindable var satellites: SatelliteConsultationStore
    private var localPosition: RadioLocation? { RadioLocation(latitude: guide.latitude, longitude: guide.longitude) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Consulta", selection: $store.section) {
                    ForEach(RadioConsultationSection.allCases) { section in Text(section.rawValue).tag(section) }
                }.pickerStyle(.segmented)
                switch store.section {
                case .frequency: frequencyLookup
                case .repeaters: repeaterLookup
                case .callsigns: callsignLookup
                case .aprs: aprsLookup
                case .satellites: satelliteLookup
                }
            }
            .padding(20)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .task { await store.activate(); await satellites.activate() }
        .onDisappear { aprs.stop() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Consultas de radio").font(.largeTitle.weight(.semibold))
                Text("Frecuencias chilenas, estaciones cercanas y ventanas de recepción").foregroundStyle(.secondary)
            }
            Spacer()
            if let localPosition {
                Label(String(format: "%.3f, %.3f", localPosition.latitude, localPosition.longitude), systemImage: "location")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Text("Guarda una ubicación en Condiciones y propagación para consultas locales.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var frequencyLookup: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Buscar por frecuencia") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("MHz", text: $store.frequencyMHz).textFieldStyle(.roundedBorder).frame(width: 145)
                        Picker("Perfil del decodificador", selection: $store.chosenMode) {
                            ForEach(RadioMode.allCases.filter(\.isAudioAvailable)) { mode in Text(mode.title).tag(mode) }
                        }.frame(maxWidth: 300)
                        Button {
                            receiver.select(store.chosenMode)
                            receiver.rfModulation = store.selectedProfile.modulation
                            receiver.rfBandwidth = store.selectedProfile.rfBandwidth
                            if let frequency = RadioConsultationStore.parseFrequency(store.frequencyMHz) {
                                receiver.detail = String(format: "Sintoniza SDR++ manualmente en %.5f MHz · %@ · filtro %.0f Hz. La app solo recibe el audio.", locale: Locale(identifier: "en_US_POSIX"), frequency, store.selectedProfile.modulation.rawValue, store.selectedProfile.rfBandwidth)
                            }
                        } label: { Label("Preparar recepción", systemImage: "waveform") }
                            .buttonStyle(.borderedProminent)
                            .disabled((RadioConsultationStore.parseFrequency(store.frequencyMHz) ?? 0) <= 0)
                    }
                    if let frequency = RadioConsultationStore.parseFrequency(store.frequencyMHz), frequency > 0 {
                        if store.matchedBands.isEmpty {
                            Label("La tabla consultada no identifica esta frecuencia como segmento de radioaficionados.", systemImage: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.matchedBands) { band in
                                Label("\(band.lowerMHz.formatted(.number.precision(.fractionLength(0...4))))–\(band.upperMHz.formatted(.number.precision(.fractionLength(0...4))) ) MHz · \(band.service) · \(band.status)\(band.satellite ? " · satélite" : "")", systemImage: band.satellite ? "satellite" : "checkmark.seal")
                            }
                        }
                    } else {
                        Text("Introduce una frecuencia positiva en MHz; se acepta coma o punto decimal.").foregroundStyle(.orange)
                    }
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow { Text("Demodulación SDR").foregroundStyle(.secondary); Text(store.selectedProfile.modulation.rawValue) }
                        GridRow { Text("Ancho RF").foregroundStyle(.secondary); Text("\(Int(store.selectedProfile.rfBandwidth)) Hz") }
                        GridRow { Text("Audio para el decodificador").foregroundStyle(.secondary); Text(store.selectedProfile.audioBand) }
                        GridRow { Text("Centro de audio").foregroundStyle(.secondary); Text("\(Int(store.selectedProfile.center)) Hz") }
                    }
                    Text(store.selectedProfile.note).font(.caption).foregroundStyle(.secondary)
                    Text("La consulta aplica a las asignaciones de radioaficionado publicadas por SUBTEL; no caracteriza otros servicios ni reemplaza las reglas de la licencia. Sintoniza la frecuencia RF manualmente en SDR++ y envía su audio a la entrada seleccionada en RadioWorkbench.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            HStack {
                Link("Fuente oficial · SUBTEL, tabla 2025", destination: ChileBandAllocation.source)
                Text("Actualización publicada: \(ChileBandAllocation.updatedAt)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var repeaterLookup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Repetidoras de Chile").font(.title2.weight(.semibold))
                    Text(store.repeaterStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Link("Abrir SUBTEL", destination: SUBTELDataService.directoryURL)
                Button { Task { await store.refreshRepeaters() } } label: { Label("Actualizar", systemImage: "arrow.clockwise") }.disabled(store.repeaterBusy)
                if store.repeaterBusy { ProgressView().controlSize(.small) }
            }
            TextField("Buscar indicativo, región o comuna", text: $store.repeaterSearch).textFieldStyle(.roundedBorder)
            HStack(alignment: .top, spacing: 14) {
                List(selection: Binding(get: { store.selectedRepeaterID }, set: { value in store.chooseRepeater(value.flatMap { id in store.repeaters.first(where: { $0.id == id }) }) })) {
                    ForEach(store.filteredRepeaters) { repeater in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repeater.id).font(.headline)
                            Text([repeater.comuna, repeater.region].filter { !$0.isEmpty }.joined(separator: " · ").isEmpty ? "Ubicación no publicada" : [repeater.comuna, repeater.region].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(repeater.id)
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 260, idealWidth: 330, maxWidth: 400, minHeight: 390)

                VStack(alignment: .leading, spacing: 10) {
                    if let repeater = store.selectedRepeater {
                        Text(repeater.id).font(.title2.weight(.semibold))
                        Text([repeater.comuna, repeater.region].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                            GridRow { Text("RX de la repetidora").foregroundStyle(.secondary); Text(repeater.receiveMHz.map { "\($0, specifier: "%.5f") MHz" } ?? "Sin dato") }
                            GridRow { Text("TX de la repetidora").foregroundStyle(.secondary); Text(repeater.transmitMHz.map { "\($0, specifier: "%.5f") MHz" } ?? "Sin dato") }
                            GridRow { Text("Tono").foregroundStyle(.secondary); Text(repeater.toneHz.map { "\($0, specifier: "%.1f") Hz" } ?? "Sin dato") }
                        }
                        if !repeater.detail.isEmpty { Text(repeater.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        Divider()
                        Text("Coordenadas del sitio").font(.headline)
                        HStack {
                            TextField("Latitud", text: $store.repeaterLatitude).frame(width: 135)
                            TextField("Longitud", text: $store.repeaterLongitude).frame(width: 135)
                        }
                        if repeater.latitude == nil || repeater.longitude == nil {
                            Text("SUBTEL no entregó coordenadas parseables para esta fila. Puedes ingresarlas manualmente para usar el perfil de relieve.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Copiar TX de repetidora") {
                                if let value = repeater.transmitMHz { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(value), forType: .string) }
                            }.disabled(repeater.transmitMHz == nil)
                            Button("Usar como destino ITM") { openTerrain(for: repeater) }
                                .buttonStyle(.borderedProminent).disabled(store.makeSelectedRepeaterLocation() == nil)
                        }
                        Text("El perfil compara terreno AMSL más altura de antena AGL y calcula difracción ITM. El listado oficial indica licencia del sitio; no confirma que el repetidor esté encendido o que puedas recibirlo ahora.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView("Selecciona una repetidora", systemImage: "antenna.radiowaves.left.and.right", description: Text("Después podrás revisar las frecuencias publicadas y abrir el análisis de relieve del enlace."))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 390, alignment: .topLeading)
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var callsignLookup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Indicativos y licencias").font(.title2.weight(.semibold))
                    Text(store.callsignStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Link("Abrir SUBTEL", destination: SUBTELDataService.directoryURL)
                Button { Task { await store.refreshCallsigns() } } label: { Label("Actualizar", systemImage: "arrow.clockwise") }.disabled(store.callsignBusy)
                if store.callsignBusy { ProgressView().controlSize(.small) }
            }
            TextField("Buscar indicativo (ej. CE3…)", text: $store.callsignSearch).textFieldStyle(.roundedBorder)
            if store.callsignSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Busca un indicativo", systemImage: "person.text.rectangle", description: Text("Consulta el listado público de licencias de radioaficionado en Chile."))
                    .frame(minHeight: 250)
            } else if store.matchingCallsigns.isEmpty {
                ContentUnavailableView("Sin coincidencias", systemImage: "magnifyingglass", description: Text("Actualiza el listado o comprueba el indicativo."))
                    .frame(minHeight: 250)
            } else {
                Table(store.matchingCallsigns) {
                    TableColumn("Indicativo", value: \.id)
                    TableColumn("Categoría", value: \.category)
                    TableColumn("Zona publicada", value: \.region)
                    TableColumn("Vencimiento", value: \.expiresOn)
                }.frame(minHeight: 280)
            }
            Text("La app conserva únicamente indicativo, categoría, zona publicada y fecha de vencimiento; excluye nombres y números de licencia del PDF.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var aprsLookup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("APRS cercano · flujo de Internet").font(.title2.weight(.semibold))
                    Text(aprs.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                if aprs.connected { Button("Detener") { aprs.stop() } }
                else { Button("Conectar solo recepción") { aprs.connect(location: localPosition) }.buttonStyle(.borderedProminent) }
            }
            HStack {
                TextField("Tu indicativo", text: $aprs.callsign).textFieldStyle(.roundedBorder).frame(width: 190)
                Picker("Radio", selection: $aprs.radiusKilometers) {
                    Text("25 km").tag(25.0); Text("50 km").tag(50.0); Text("100 km").tag(100.0); Text("200 km").tag(200.0)
                }.frame(width: 150)
                if localPosition == nil { Text("Guarda tu ubicación primero.").font(.caption).foregroundStyle(.orange) }
            }
            Text("APRS-IS recibe paquetes que llegaron a la red por gateways; no es una captura RF local ni confirma que SDR++ pueda oír la estación. La consulta envía al servidor tu indicativo y una cuadrícula aproximada de ubicación para filtrar; usa passcode −1 y no transmite paquetes.")
                .font(.caption).foregroundStyle(.secondary)
            if aprs.positions.isEmpty {
                ContentUnavailableView(aprs.connected ? "Esperando paquetes" : "Sin consulta activa", systemImage: "antenna.radiowaves.left.and.right", description: Text("Las estaciones aparecerán cuando el flujo publique posiciones dentro del radio elegido."))
                    .frame(minHeight: 250)
            } else {
                Table(aprs.positions, selection: $aprs.selectedPositionID) {
                    TableColumn("Estación", value: \.id)
                    TableColumn("Latitud") { station in Text(station.latitude, format: .number.precision(.fractionLength(4))) }
                    TableColumn("Longitud") { station in Text(station.longitude, format: .number.precision(.fractionLength(4))) }
                    TableColumn("Recibida") { station in Text(station.receivedAt, style: .time) }
                    TableColumn("Comentario") { station in Text(station.comment).lineLimit(1) }
                }.frame(minHeight: 300)
                if let selected = aprs.positions.first(where: { $0.id == aprs.selectedPositionID }) {
                    HStack {
                        Text("\(selected.id) · símbolo \(selected.symbol) · vía \(selected.path)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Usar posición como destino ITM") {
                            if let destination = RadioLocation(latitude: selected.latitude, longitude: selected.longitude) { openTerrain(destination: destination, frequencyMHz: nil) }
                        }
                            .buttonStyle(.borderedProminent)
                    }
                    Text(selected.comment).font(.caption).textSelection(.enabled)
                }
            }
        }
    }

    private var satelliteLookup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Satélites con radioafición").font(.title2.weight(.semibold))
                    Text(satellites.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button { Task { await satellites.refresh() } } label: { Label("Actualizar datos", systemImage: "arrow.clockwise") }.disabled(satellites.busy)
                if satellites.busy { ProgressView().controlSize(.small) }
            }
            if let catalog = satellites.snapshot {
                Picker("Satélite", selection: Binding(get: { satellites.selectedID }, set: { satellites.selectSatellite($0) })) {
                    ForEach(catalog.satellites) { satellite in Text("\(satellite.name) · NORAD \(satellite.noradID)").tag(Optional(satellite.id)) }
                }
                if let satellite = satellites.selected {
                    GroupBox(satellite.name) {
                        VStack(alignment: .leading, spacing: 8) {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                                GridRow { Text("Bajada publicada").foregroundStyle(.secondary); Text(satellite.downlinkSummary.isEmpty ? "Sin dato" : satellite.downlinkSummary) }
                                GridRow { Text("Subida publicada").foregroundStyle(.secondary); Text(satellite.uplinkSummary.isEmpty ? "Sin dato" : satellite.uplinkSummary) }
                                GridRow { Text("Baliza").foregroundStyle(.secondary); Text(satellite.transmitters.compactMap(\.beacon).joined(separator: " · ").nilIfEmpty ?? "Sin dato") }
                                GridRow { Text("Modo declarado").foregroundStyle(.secondary); Text(satellite.modeSummary.nilIfEmpty ?? "Sin dato") }
                                GridRow { Text("Época orbital").foregroundStyle(.secondary); Text(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!).format(satellite.orbit.epoch) + " UTC") }
                                GridRow {
                                    Text("Estado reportado · 72 h").foregroundStyle(.secondary)
                                    if let report = satellites.latestStatus {
                                        Text("\(report.report) · \(report.reportedAt.formatted(date: .abbreviated, time: .shortened))")
                                    } else { Text("Sin reporte reciente") }
                                }
                            }
                            HStack {
                                Link("Frecuencias · AMSAT/SatNOGS", destination: URL(string: "https://satdb.amsat.org/")!)
                                Link("Reportes AMSAT", destination: URL(string: "https://www.amsat.org/status/")!)
                                Link("Elementos GP · CelesTrak", destination: URL(string: "https://celestrak.org/NORAD/elements/")!)
                                Link("Licencia CC BY-SA", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                            }.font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                HStack {
                    Button { satellites.calculatePasses(location: localPosition) } label: {
                        if satellites.calculatingPasses { Label("Calculando…", systemImage: "clock") }
                        else { Label("Calcular próximos pases · 48 h", systemImage: "moon.stars") }
                    }.disabled(satellites.selected == nil || localPosition == nil || satellites.calculatingPasses)
                    if localPosition == nil { Text("Guarda la ubicación antes de calcular.").font(.caption).foregroundStyle(.orange) }
                }
                if !satellites.passes.isEmpty {
                    Table(satellites.passes) {
                        TableColumn("AOS · hora local") { pass in Text(pass.aos, style: .time) }
                        TableColumn("Elevación máxima") { pass in Text("\(pass.maximumElevation, specifier: "%.1f")°") }
                        TableColumn("Máximo") { pass in Text(pass.maximumAt, style: .time) }
                        TableColumn("LOS · hora local") { pass in Text(pass.los, style: .time) }
                        TableColumn("Duración") { pass in Text("\(Int(pass.los.timeIntervalSince(pass.aos) / 60)) min") }
                    }.frame(minHeight: 170)
                }
                Text("Los pases usan los elementos orbitales descargados y un modelo Kepler con corrección secular J2, no SGP4. Sirven para planificar una escucha aproximada; comprueba TLE reciente, horizonte local, frecuencia activa y Doppler antes del pase. No controla SDR++ automáticamente.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Catálogo todavía no descargado", systemImage: "satellite", description: Text("Actualiza para combinar las frecuencias de radioaficionado de AMSAT/SatNOGS con las órbitas de CelesTrak."))
                    .frame(minHeight: 260)
            }
        }
    }

    private func openTerrain(for repeater: VHFRepeater) {
        guard let location = store.makeSelectedRepeaterLocation() else { return }
        openTerrain(destination: location, frequencyMHz: repeater.transmitMHz ?? repeater.receiveMHz)
    }

    private func openTerrain(destination: RadioLocation, frequencyMHz: Double?) {
        propagation.setTerrainTarget(destination)
        if let frequencyMHz, frequencyMHz >= 20, frequencyMHz <= 20_000 { propagation.terrainFrequencyMHz = RadioConsultationStore.coordinateText(frequencyMHz) }
        if let localPosition, propagation.terrainOrigin == nil { propagation.setTerrainOrigin(localPosition) }
        receiver.stop(); receiver.destination = .propagation
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
