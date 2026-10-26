import SwiftUI
import RadioCore

struct BroadcastGuideView: View {
    @Bindable var guide: BroadcastStore
    let onPlanHF: (BroadcastEntry) -> Void
    let onRecord: (BroadcastEntry) -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let rows = guide.results(at: context.date)
            let hfccMatches = guide.hfccMatches(for: rows)
            VStack(alignment: .leading, spacing: 12) {
                header(at: context.date)
                filters
                if guide.invalidFrequency { Text("Introduce una frecuencia positiva en kHz, por ejemplo 9710.").font(.caption).foregroundStyle(.red) }
                Text(AppLocalization.text(guide.status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text(AppLocalization.text(guide.alertStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let snapshot = guide.snapshot {
                    HStack {
                        Text("EiBi · \(snapshot.season.uppercased()) · \(rows.count) de \(snapshot.entries.count) registros")
                        Spacer()
                        Text("Descarga: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(AppLocalization.text(guide.hfccStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if snapshot.season != BroadcastCalendar.season(at: context.date) {
                        Label("La copia corresponde a otra temporada o a una importación. Comprueba su vigencia.", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
                    }
                }
                if rows.isEmpty {
                    ContentUnavailableView(guide.snapshot == nil ? "Sin lista de emisoras" : "Sin coincidencias", systemImage: "antenna.radiowaves.left.and.right", description: Text(guide.snapshot == nil ? "Conéctate y pulsa Actualizar, o importa una lista CSV de EiBi." : "Cambia los filtros o desactiva Previstas ahora."))
                } else {
                    Table(rows, selection: $guide.selectedID) {
                        TableColumn("kHz") { e in Text(e.frequencyKHz.formatted(.number.precision(.fractionLength(0...2)))).monospacedDigit() }.width(min: 65, ideal: 80, max: 100)
                        TableColumn("Emisora") { e in
                            HStack(spacing: 5) {
                                if guide.favorites.contains(e.id) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                if guide.alertFavorites.contains(e.id) { Image(systemName: "bell.badge.fill").foregroundStyle(.orange) }
                                Text(e.station)
                            }
                        }.width(min: 140, ideal: 230)
                        TableColumn("UTC", value: \.time).width(90)
                        TableColumn("Modo / filtro") { e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hfccMatches[e.id]?.modulation ?? e.modulation)
                                Text(e.tuningSuggestion).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.width(min: 160, ideal: 210)
                        TableColumn("TX HFCC") { e in
                            Text(hfccMatches[e.id]?.powerKW.map { "\($0) kW" } ?? "—").monospacedDigit()
                        }.width(min: 75, ideal: 90)
                        TableColumn("Idioma", value: \.language).width(65)
                        TableColumn("País", value: \.country).width(60)
                        TableColumn("Estado") { e in Text(BroadcastCalendar.activity(e, at: context.date, season: guide.snapshot?.season ?? "").rawValue).foregroundStyle(BroadcastCalendar.activity(e, at: context.date, season: guide.snapshot?.season ?? "") == .scheduled ? .green : .secondary) }.width(min: 100, ideal: 125)
                    }
                    .contextMenu(forSelectionType: String.self) { ids in
                        if let id = ids.first, let e = rows.first(where: { $0.id == id }) {
                            Button(guide.favorites.contains(id) ? "Quitar de favoritos" : "Guardar favorito") { guide.toggleFavorite(e) }
                            Button("Copiar frecuencia") { copyFrequency(e) }
                            Button("Planificar escucha") { onPlanHF(e) }
                            Button("Registrar escucha en biblioteca…") { onRecord(e) }
                        }
                    }
                    .frame(minHeight: 180)
                }
                if let e = guide.selectedEntry {
                    BroadcastDetailView(entry: e, hfcc: guide.hfccMatch(for: e), guide: guide, onPlanHF: onPlanHF, onRecord: onRecord)
                        .frame(maxHeight: 300)
                }
                HStack {
                    Text("Estado calculado desde el horario UTC; la recepción se confirma escuchando la señal.")
                    Spacer()
                    Link("Fuente y códigos EiBi", destination: URL(string: "http://www.eibispace.de/dx/README.TXT")!)
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .task { await guide.activate() }
    }
    private func header(at date: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Guía de radios").font(.largeTitle.weight(.semibold))
                Text("Horarios EiBi y coincidencias técnicas HFCC de frecuencia y horario; revisa el transmisor").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(secondsFromGMT: 0)!)) + " UTC").monospacedDigit()
                Text(guide.autoRefreshEnabled ? AppLocalization.text("Actualización automática cada {0} h").replacingOccurrences(of: "{0}", with: String(guide.autoRefreshHours)) : AppLocalization.text("Actualización manual")).font(.caption).foregroundStyle(.secondary)
            }
            Button { Task { await guide.refresh() } } label: { Label("Actualizar", systemImage: "arrow.clockwise") }.disabled(guide.busy)
            if guide.busy { ProgressView().controlSize(.small) }
            Button("Importar CSV…") { guide.importFile() }.disabled(guide.busy)
        }
    }
    private var filters: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Buscar emisora, país o idioma", text: $guide.search).textFieldStyle(.roundedBorder)
                Picker("Banda", selection: $guide.band) {
                    ForEach(["Todas","OL","OM","OC"] + BroadcastEntry.bands.map(\.0), id: \.self) { Text(AppLocalization.text($0)).tag($0) }
                }.frame(width: 165)
                Picker("Tipo", selection: $guide.category) { ForEach(["Todas","Radiodifusión","Utilitarias"], id: \.self) { Text(AppLocalization.text($0)) } }.frame(width: 190)
            }
            HStack {
                TextField("Frecuencia kHz", text: $guide.frequency).textFieldStyle(.roundedBorder).frame(width: 125)
                Picker("±", selection: $guide.tolerance) { ForEach([0.0,1,5,10], id: \.self) { Text("\($0, specifier: "%.0f") kHz").tag($0) } }.frame(width: 110)
                Picker("Idioma", selection: $guide.language) {
                    Text("Todos").tag("Todos")
                    ForEach(Array(Set(guide.snapshot?.entries.map(\.language).filter { !$0.isEmpty } ?? [])).sorted(), id: \.self) { code in
                        Text("\(code) · \(guide.snapshot?.reference.languages[code] ?? code)").tag(code)
                    }
                }.frame(maxWidth: 240)
                Spacer()
                Toggle("Previstas ahora", isOn: $guide.onlyNow)
                Toggle("Favoritas", isOn: $guide.onlyFavorites)
            }
        }.controlSize(.small)
    }
    private func copyFrequency(_ e: BroadcastEntry) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(e.frequencyKHz) kHz", forType: .string) }
}

struct BroadcastDetailView: View {
    let entry: BroadcastEntry
    let hfcc: HFCCTransmission?
    @Bindable var guide: BroadcastStore
    let onPlanHF: (BroadcastEntry) -> Void
    let onRecord: (BroadcastEntry) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.station).font(.title3.weight(.semibold))
                    Text("\(entry.frequencyKHz, specifier: "%.2f") kHz · \(entry.broadcastBand)").monospacedDigit()
                    Spacer()
                    Button("Copiar kHz") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(entry.frequencyKHz), forType: .string) }
                    Button("Copiar MHz") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(entry.frequencyKHz / 1000), forType: .string) }
                    Button { guide.toggleFavorite(entry) } label: { Label(guide.favorites.contains(entry.id) ? "Guardada" : "Favorito", systemImage: guide.favorites.contains(entry.id) ? "star.fill" : "star") }
                    Toggle("Avisarme", isOn: Binding(
                        get: { guide.alertFavorites.contains(entry.id) },
                        set: { guide.setFavoriteAlert(entry, enabled: $0) }
                    )).disabled(!guide.favorites.contains(entry.id))
                    Picker("Anticipación", selection: Binding(
                        get: { guide.alertLeadMinutes },
                        set: { guide.setAlertLeadMinutes($0) }
                    )) {
                        ForEach([0, 5, 10, 15], id: \.self) { minutes in Text(minutes == 0 ? "A la hora" : "\(minutes) min antes").tag(minutes) }
                    }.frame(width: 130)
                }
                let ref = guide.snapshot?.reference ?? BroadcastReference()
                HStack {
                    Button("Registrar escucha en biblioteca…", systemImage: "books.vertical") { onRecord(entry) }.buttonStyle(.borderedProminent)
                    Button("Planificar escucha", systemImage: "arrow.up.right.square") { onPlanHF(entry) }
                    Button("Copiar ficha") {
                        let site = ref.site(for: entry)
                        let text = "\(entry.station)\n\(entry.frequencyKHz) kHz · \(entry.modulation)\n\(entry.time) UTC · días \(entry.days)\nSitio: \(site?.name ?? entry.site)\n" + (site.map { "Coordenadas EiBi: \($0.latitude), \($0.longitude)\n" } ?? "Coordenadas: pendientes\n") + "Potencia HFCC candidata: \(hfcc?.powerKW.map { "\($0) kW" } ?? "sin dato") · sitio \(hfcc?.siteCode ?? "sin verificar")\nFuente: EiBi · \(guide.snapshot?.season ?? "")"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    }
                    Text("El planificador copia lo disponible y señala los campos pendientes.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("País: \(ref.countries[entry.country] ?? entry.country) [\(entry.country)]")
                        Text("Idioma: \(ref.languages[entry.language] ?? entry.language)")
                        Text("Destino: \(ref.targetName(entry.target))")
                        Text("UTC: \(entry.time) · Días: \(entry.days.isEmpty ? "diario" : entry.days)")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modo: \(hfcc?.modulation ?? entry.modulation)")
                        Text(entry.tuningSuggestion)
                        Text("Sitio: \(ref.site(for: entry)?.name ?? (entry.site.isEmpty ? "No especificado" : entry.site))")
                        if let site = ref.site(for: entry) {
                            Text("\(site.latitude, specifier: "%.3f")°, \(site.longitude, specifier: "%.3f")° · EiBi")
                            if let (lat,lon) = guide.position {
                                let (km,bearing) = site.distanceAndBearing(latitude: lat, longitude: lon)
                                Text("\(km, specifier: "%.0f") km · rumbo \(bearing, specifier: "%.0f")°")
                            }
                        }
                        if let date = guide.snapshot?.sourceModifiedAt { Text("Archivo fuente: \(date.formatted(date: .abbreviated, time: .shortened))") }
                        if entry.persistence % 90 == 6 { Text("Vigencia parcial: \(entry.startDate)–\(entry.stopDate) (DDMM)") }
                    }
                }.font(.caption).textSelection(.enabled)
                Text(guide.alertFavorites.contains(entry.id)
                    ? "Se agenda una notificación macOS para la próxima emisión prevista de esta emisora, según su horario UTC."
                    : "Guarda la emisora y activa Avisarme para recibir una notificación antes de su próxima emisión prevista.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let hfcc {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("HFCC · coincidencia de frecuencia/horario; revisa el sitio \(hfcc.siteCode)", systemImage: "info.circle")
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 16) {
                            Text("Potencia TX: \(hfcc.powerKW.map { "\($0) kW (\($0 * 1_000) W)" } ?? "sin dato")")
                            Text("Rumbo máximo: \(hfcc.azimuthDegrees.map { "\($0)°" } ?? "no indicado")")
                            Text("Zona CIRAF: \(hfcc.targetArea.isEmpty ? "no indicada" : hfcc.targetArea)")
                            Text("Idioma: \(hfcc.language)")
                        }
                        Text("HFCC describe una asignación programada, no confirma transmisión, potencia radiada efectiva ni cobertura recibida. Fuente: \(hfcc.broadcasterCode.isEmpty ? "HFCC" : "HFCC \(hfcc.broadcasterCode)") · \(hfcc.startUTC)–\(hfcc.stopUTC) UTC · días \(hfcc.days).")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Sin coincidencia HFCC inequívoca: se conservan los datos EiBi y no se atribuye potencia TX.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Tu ubicación:").font(.caption)
                    TextField("Latitud", text: $guide.latitude).frame(width: 100)
                    TextField("Longitud", text: $guide.longitude).frame(width: 100)
                    Button("Guardar") { guide.saveLocation() }
                    Text("Coordenadas manuales para distancia y rumbo.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link("WebSDR Twente", destination: URL(string: "http://websdr.ewi.utwente.nl:8901/")!)
                }.textFieldStyle(.roundedBorder).controlSize(.small)
                DisclosureGroup("Registro original") { Text(entry.raw).font(.caption.monospaced()).textSelection(.enabled) }
            }.padding(12)
        }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
