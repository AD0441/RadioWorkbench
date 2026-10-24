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
        .onChange(of: localPosition) { _, _ in satellites.clearPasses() }
        .onDisappear { if receiver.destination != .receptionMap { aprs.stop() } }
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
                            if store.chosenMode == .hell { receiver.applyHellVariant() }
                            if let frequency = RadioConsultationStore.parseFrequency(store.frequencyMHz) {
                                receiver.detail = String(format: "Sintoniza SDR++ manualmente en %.5f MHz · %@ · filtro %.0f Hz. La app solo recibe el audio.", locale: Locale(identifier: "en_US_POSIX"), frequency, receiver.rfModulation.rawValue, receiver.rfBandwidth)
                            }
                        } label: { Label("Preparar recepción", systemImage: "waveform") }
                            .buttonStyle(.borderedProminent)
                            .disabled((RadioConsultationStore.parseFrequency(store.frequencyMHz) ?? 0) <= 0)
                    }
                    Button("Preparar sintonía optativa en SDR++…") {
                        if let frequency = RadioConsultationStore.parseFrequency(store.frequencyMHz) {
                            receiver.stop()
                            receiver.rigctl.prepare(mhz: frequency, modulation: store.selectedProfile.modulation,
                                bandwidth: store.selectedProfile.rfBandwidth, source: "Consulta de frecuencia · \(store.chosenMode.title)")
                            receiver.destination = .rigctl
                        }
                    }.disabled((RadioConsultationStore.parseFrequency(store.frequencyMHz) ?? 0) <= 0)
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
                        RepeaterMapPanel(store: store, observer: localPosition)
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
                        RepeaterMapPanel(store: store, observer: localPosition)
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
                                GridRow { Text("Fuente orbital").foregroundStyle(.secondary); Text(catalog.orbitSource ?? "Copia anterior") }
                                GridRow { Text("Consulta de órbitas").foregroundStyle(.secondary); Text(catalog.orbitsFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Sin fecha") }
                                GridRow { Text("Consulta de frecuencias").foregroundStyle(.secondary); Text(catalog.frequenciesFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Sin descarga válida") }
                                GridRow {
                                    Text("Estado reportado · 72 h").foregroundStyle(.secondary)
                                    TimelineView(.periodic(from: .now, by: 60)) { context in
                                        if let report = satellites.latestStatus(for: satellite, now: context.date) {
                                            Text("\(report.report) · \(report.reportedAt.formatted(date: .abbreviated, time: .shortened)) · reporte de usuario, no garantía de emisión")
                                        } else { Text("Sin reporte de las últimas 72 h; la copia puede estar sin conexión") }
                                    }
                                }
                            }
                            if Date().timeIntervalSince(satellite.orbit.epoch) > 7 * 86_400 {
                                Text("Época orbital de más de siete días: actualiza antes de planificar.").font(.caption).foregroundStyle(.orange)
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
                satellitePassControls
                if !satellites.nextHour.isEmpty { satelliteHourResults }
                if let satellite = satellites.selected {
                    satelliteDownlinkSelector(satellite)
                }
                if !satellites.passes.isEmpty {
                    Table(satellites.passes, selection: Binding(get: { satellites.selectedPassID }, set: { satellites.selectPass($0) })) {
                        TableColumn("AOS · fecha/hora local") { pass in
                            VStack(alignment: .leading) {
                                Text(pass.aos.formatted(date: .abbreviated, time: .shortened))
                                if pass.aosClipped { Text("Visible al comienzo del cálculo; AOS no resuelto").font(.caption2) }
                            }
                        }
                        TableColumn("Elevación máxima") { pass in Text("\(pass.maximumElevation, specifier: "%.1f")°") }
                        TableColumn("Máximo") { pass in Text(pass.maximumAt, style: .time) }
                        TableColumn("LOS · hora local") { pass in
                            VStack(alignment: .leading) {
                                Text(pass.los, style: .time)
                                if pass.losClipped { Text("Continúa visible; LOS no resuelto").font(.caption2) }
                            }
                        }
                        TableColumn("Duración") { pass in Text("\(Int(pass.los.timeIntervalSince(pass.aos) / 60)) min") }
                    }.frame(minHeight: 170)
                }
                if let pass = satellites.selectedPass, let observer = satellites.observer, !satellites.track.isEmpty {
                    SatellitePassMapPanel(pass: pass, track: satellites.track, observer: observer, downlink: satellites.selectedDownlink)
                }
                Text("Pases de radio calculados con SGP4/SDP4 y WGS84. El horizonte ideal no incluye montañas, edificios ni altura local de la antena. No se calcula visibilidad óptica (iluminación, sombra y oscuridad) ni una probabilidad de éxito calibrada. La frecuencia publicada no asegura actividad durante el pase; sintonía y Doppler se ajustan manualmente en el SDR.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Catálogo todavía no descargado", systemImage: "satellite", description: Text("Actualiza para combinar las frecuencias de radioaficionado de AMSAT/SatNOGS con las órbitas de CelesTrak."))
                    .frame(minHeight: 260)
            }
        }
    }

    private var satellitePassControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { satellites.searchNextHour(location: localPosition) } label: {
                    Label("Buscar pases en la próxima hora", systemImage: "clock.arrow.circlepath")
                }.buttonStyle(.borderedProminent).disabled(localPosition == nil || satellites.calculatingPasses)
                Button("Pases del seleccionado · 48 h") { satellites.calculatePasses(location: localPosition) }
                    .disabled(satellites.selected == nil || localPosition == nil || satellites.calculatingPasses)
                if satellites.calculatingPasses {
                    ProgressView().controlSize(.small)
                    Button("Cancelar") { satellites.cancelPassSearch() }
                }
            }
            HStack {
                Picker("Elevación máxima mínima", selection: $satellites.minimumElevation) {
                    Text("5°").tag(5.0); Text("10°").tag(10.0); Text("20°").tag(20.0); Text("30°").tag(30.0)
                }.frame(width: 290).disabled(satellites.calculatingPasses)
                Toggle("Solo satélites con bajada publicada", isOn: $satellites.onlyPublishedDownlinks)
                    .disabled(satellites.calculatingPasses)
            }.font(.caption)
            if let position = satellites.searchObserver ?? satellites.observer ?? localPosition {
                Text("Observador usado: \(position.latitude, specifier: "%.4f"), \(position.longitude, specifier: "%.4f") · tiempos locales. Cambiar de ubicación requiere recalcular.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Guarda la ubicación antes de calcular.").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var satelliteHourResults: some View {
        GroupBox("Pases RF · próximos 60 minutos") {
            VStack(alignment: .leading, spacing: 8) {
                if let window = satellites.searchWindow {
                    Text("Ventana \(window.start.formatted(date: .abbreviated, time: .shortened)) – \(window.end.formatted(date: .omitted, time: .shortened)) · AOS y LOS completos cuando se resuelve el cruce del horizonte.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(satellites.nextHour) { result in
                            satelliteOpportunityRow(result)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 330)
                Text("Índice /100: elevación dentro de la ventana 0–50 + minutos útiles (hasta 10) 0–30 + actualidad orbital (hasta 7 días) 0–20. No es un porcentaje de éxito. Compatibilidad de antena/receptor, actividad, obstrucciones y ruido pendientes de evaluar; sin historial comparable para calibrarlo.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(6)
        }
    }

    private func satelliteOpportunityRow(_ result: SatellitePassOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(result.satelliteName) · NORAD \(result.satelliteID)").font(.headline)
                Spacer()
                Text("Índice \(result.factors.score)/100").font(.subheadline.monospacedDigit()).help(result.factors.explanation)
                Button("Ver pase y bajada") { satellites.showOpportunity(result) }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(result.pass.los <= context.date ? "Pase terminado; vuelve a buscar" : result.pass.aos <= context.date ? "En curso" : "Comienza en \(max(1, Int(ceil(result.pass.aos.timeIntervalSince(context.date) / 60)))) min")
                    .font(.caption).foregroundStyle(result.pass.los <= context.date ? Color.secondary : Color.orange)
            }
            Text("AOS \(result.pass.aos.formatted(date: .omitted, time: .shortened)) · máximo \(result.pass.maximumElevation, specifier: "%.1f")° a \(result.pass.maximumAt.formatted(date: .omitted, time: .shortened)) · LOS \(result.pass.los.formatted(date: .omitted, time: .shortened)) · \(Int(result.factors.usefulSeconds / 60)) min dentro de la ventana")
                .font(.caption.monospacedDigit())
            Text(result.downlinks.map { "\($0.label) · \($0.mode)" }.joined(separator: " | ").nilIfEmpty ?? "Sin bajada publicada; compatibilidad desconocida")
                .font(.caption).textSelection(.enabled)
            Text("Elevación en la ventana \(result.factors.elevationInWindow, specifier: "%.1f")° · época orbital hace \(result.factors.orbitAgeDays, specifier: "%.1f") días · \(result.report.map { "AMSAT: \($0.report), \($0.reportedAt.formatted(date: .abbreviated, time: .shortened))" } ?? "Sin reporte AMSAT reciente") · estado por transmisor sin verificar")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func satelliteDownlinkSelector(_ satellite: AmateurSatellite) -> some View {
        GroupBox("Preparar la bajada seleccionada") {
            VStack(alignment: .leading, spacing: 8) {
                if satellite.downlinks.isEmpty {
                    Text("No hay una frecuencia numérica de bajada en el catálogo. El mapa no usará una frecuencia de ejemplo para calcular Doppler.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Transmisor / baliza", selection: Binding(get: { satellites.selectedDownlink?.id }, set: { satellites.selectedDownlinkID = $0 })) {
                        ForEach(satellite.downlinks) { link in Text("\(link.label) · \(link.mode)").tag(Optional(link.id)) }
                    }
                    if let link = satellites.selectedDownlink {
                        if link.isPassband {
                            Text("Rango de transpondedor: el Doppler usa el centro \(link.nominalMHz, specifier: "%.6f") MHz como referencia. Elige la señal concreta dentro del rango en tu SDR.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let decoder = satelliteDecoder(link) {
                            Button("Preparar recepción · \(decoder.title)") { prepareSatellite(link, decoder: decoder) }
                        } else {
                            Text("Modo publicado sin un decodificador de audio equivalente confirmado. Usa la frecuencia y el modo indicados para preparar tu SDR manualmente.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    private func satelliteDecoder(_ link: SatelliteDownlink) -> RadioMode? {
        let mode = link.mode.uppercased()
        if mode.contains("SSTV") { return .sstv }
        if mode.contains("1K2") && (mode.contains("AFSK") || mode.contains("APRS")) { return .packet }
        if mode.contains("FT8") { return .ft8 }
        if mode.contains("FT4") { return .ft4 }
        if mode == "CW" { return .morse }
        if mode.contains("D-STAR") { return .digitalVoice }
        return nil
    }

    private func prepareSatellite(_ link: SatelliteDownlink, decoder: RadioMode) {
        receiver.select(decoder)
        if decoder == .sstv || decoder == .packet {
            receiver.rfModulation = link.nominalMHz >= 30 ? .fm : .usb
            receiver.rfBandwidth = link.nominalMHz >= 30 ? 12_500 : 3_000
        }
        if decoder == .digitalVoice {
            receiver.settings.digitalVoiceProtocol = .dstar
            let profile = decoder.receptionProfile(settings: receiver.settings)
            receiver.rfModulation = profile.modulation; receiver.rfBandwidth = profile.rfBandwidth
        }
        receiver.detail = String(format: "Sintoniza manualmente %.6f MHz · %@ · filtro %.0f Hz. %@ · %@. La frecuencia de catálogo no garantiza actividad.",
            link.nominalMHz, receiver.rfModulation.rawValue, receiver.rfBandwidth, satellites.selected?.name ?? "Satélite", link.mode)
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
