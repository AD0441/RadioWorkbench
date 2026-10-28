import SwiftUI
import RadioCore

struct BandInformationPanel: View {
    let store: PropagationStore
    let location: RadioLocation?
    let date: Date
    private var day: Bool? { location.map { $0.solarElevation(at: date) >= 0 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let scales = store.weather.scales, (-300...900).contains(date.timeIntervalSince(scales.observedAt)) {
                let levels = [scales.radio ?? 0, scales.radiation ?? 0, scales.geomagnetic ?? 0]
                if levels.contains(where: { $0 >= 1 }) {
                    Label("Aviso NOAA: R\(scales.radio.map(String.init) ?? "—") · S\(scales.radiation.map(String.init) ?? "—") · G\(scales.geomagnetic.map(String.init) ?? "—"). Pueden alterarse enlaces HF, especialmente trayectos iluminados o polares según el fenómeno.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            if let location, let grid = store.weather.absorption, grid.isFresh(at: date), let cell = grid.nearest(to: location), cell.highestAffectedMHz >= 3 {
                Label("Absorción local: el umbral de 1 dB alcanza \(cell.highestAffectedMHz, specifier: "%.1f") MHz. Revisa las bandas inferiores en D-RAP.", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            }
            GroupBox("Band Info · perspectiva HF general") {
                VStack(alignment: .leading, spacing: 10) {
                    if let info = store.weather.bandInformation {
                        HStack {
                            Text("\(info.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!))) UTC").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let day { Label("En tu ubicación: \(day ? "día" : "noche")", systemImage: day ? "sun.max" : "moon").font(.caption) }
                        }
                        if !info.isFresh(at: date) { Label("Band Info antiguo: conserva su fecha. Reintento según cadencia de la fuente.", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange).font(.caption) }
                        if store.sourceErrors[SpaceWeatherSource.bandInformation.rawValue] != nil { Text("No se pudo actualizar Band Info. Se conserva la copia disponible.").foregroundStyle(.orange).font(.caption) }
                        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
                            GridRow {
                                Text("Bandas").font(.caption).foregroundStyle(.secondary)
                                Label("Día", systemImage: "sun.max").font(.caption).foregroundStyle(.secondary)
                                Label("Noche", systemImage: "moon").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(info.bands) { band in
                                GridRow {
                                    Text(band.name.replacingOccurrences(of: "m-", with: "–")).fontWeight(.medium)
                                    badge(band.day, fresh: info.isFresh(at: date), active: day == true)
                                    badge(band.night, fresh: info.isFresh(at: date), active: day == false)
                                }
                            }
                        }
                        if let day, info.isFresh(at: date) {
                            let best = info.bands.filter { (day ? $0.day : $0.night) == .good }.map(\.name)
                            if !best.isEmpty { Label("Perspectiva general favorable: " + best.joined(separator: ", "), systemImage: "antenna.radiowaves.left.and.right").font(.callout).foregroundStyle(.green) }
                        }
                        if !store.bandChanges.isEmpty, let time = store.bandChangesAt {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Últimos cambios · \(time.formatted(date: .omitted, time: .shortened))", systemImage: "bell.badge").font(.caption.weight(.semibold))
                                ForEach(store.bandChanges, id: \.self) { Text(AppLocalization.text($0)).font(.caption) }
                            }.foregroundStyle(.orange)
                        }
                        Text("Estados orientativos de N0NBH/HamQSL, como los mostrados por W5MMW. Son una perspectiva general por día/noche; la predicción de tu enlace depende de ubicación, rumbo, potencia, antenas y ruido.").font(.caption).foregroundStyle(.secondary)
                        if !info.vhf.isEmpty {
                            Text("VHF · regiones de esta fuente").font(.caption.weight(.semibold))
                            ForEach(info.vhf) { entry in
                                Text("\(entry.phenomenon) · \(entry.regionTitle): \(entry.statusTitle)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Estos estados corresponden únicamente a las regiones indicadas; la cobertura regional de esta fuente es limitada.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else { Text("Band Info sin datos aún. La fuente se consulta una vez por hora.").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Link("Datos y cálculos: N0NBH / HamQSL", destination: URL(string: "https://www.hamqsl.com/solar.html")!)
                        Link("Referencia: W5MMW", destination: URL(string: "https://solar.w5mmw.net/")!)
                    }.font(.caption)
                    HStack {
                        Text("VHF: ").foregroundStyle(.secondary)
                        Link("DXrobot", destination: URL(string: "https://www.gooddx.net/")!)
                        Link("Make More Miles on VHF", destination: URL(string: "https://www.mmmonvhf.de/")!)
                        Link("G7IZU", destination: URL(string: "http://www.tvcomm.co.uk/")!)
                    }.font(.caption2)
                }.padding(8)
            }
        }
    }
    private func badge(_ condition: BandCondition, fresh: Bool, active: Bool) -> some View {
        let vivid: Color = switch condition { case .good: .green; case .fair: .orange; case .poor: .red }
        let color: Color = fresh ? vivid : .secondary
        return Label(AppLocalization.text(condition.title), systemImage: condition == .good ? "checkmark.circle.fill" : condition == .fair ? "minus.circle.fill" : "xmark.circle.fill")
            .font(.callout.weight(active ? .semibold : .regular)).foregroundStyle(color)
            .padding(.vertical, 3).padding(.horizontal, 8).background(color.opacity(active ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
