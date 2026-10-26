import SwiftUI
import RadioCore

struct SpaceWeatherPanel: View {
    let snapshot: SpaceWeatherSnapshot
    let errors: [String: String]
    let location: RadioLocation?
    let date: Date
    private var cell: AbsorptionCell? { location.flatMap { snapshot.absorption?.nearest(to: $0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                reading("Kp estimado · global", value: snapshot.kp, age: 900, units: "", source: .kp)
                reading("F10.7 · última medición", value: snapshot.flux, age: 72*3600, units: "sfu", source: .flux)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Escalas NOAA · actuales").font(.caption).foregroundStyle(.secondary)
                    Text("R\(scale(snapshot.scales?.radio)) · S\(scale(snapshot.scales?.radiation)) · G\(scale(snapshot.scales?.geomagnetic))").font(.title3.monospacedDigit())
                    stamp(snapshot.scales?.observedAt, age: 900, source: .scales)
                    Text("Radio · radiación · tormenta geomagnética").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let grid = snapshot.absorption {
                GroupBox("Absorción HF local · modelo NOAA D-RAP") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if let cell {
                                Text("Umbral de 1 dB: \(cell.highestAffectedMHz, specifier: "%.1f") MHz").font(.headline)
                                Spacer()
                                Text("Celda \(cell.latitude, specifier: "%.0f")°, \(cell.longitude, specifier: "%.0f")°").font(.caption).foregroundStyle(.secondary)
                            } else { Text("Falta ubicación para seleccionar la celda más cercana.").foregroundStyle(.secondary) }
                        }
                        stamp(grid.validAt, age: 900, source: .absorption)
                        if let cell {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 5), alignment: .leading, spacing: 10) {
                                ForEach(HFBand.all) { band in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(band.name) · \(band.frequencyMHz, specifier: "%.1f") MHz").font(.caption.weight(.medium))
                                        Text(grid.isFresh(at: date) ? (band.frequencyMHz <= cell.highestAffectedMHz ? "≥1 dB · afectada" : "<1 dB · bajo umbral") : "Dato antiguo")
                                            .font(.caption).foregroundStyle(!grid.isFresh(at: date) || band.frequencyMHz <= cell.highestAffectedMHz ? .orange : .secondary)
                                    }
                                }
                            }
                        }
                        Text("Mayor frecuencia con absorción vertical de 1 dB, estimada desde rayos X y protones. Un trayecto oblicuo puede sufrir más absorción. Un umbral bajo no demuestra que la banda esté abierta ni mide MUF, ruido local o alcance.").font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
            } else {
                Text("D-RAP sin datos disponibles. Actualizar vuelve a consultar NOAA.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Kp y F10.7 describen actividad global; el umbral D-RAP sí se consulta para tu zona. Los cambios por tormenta se muestran aparte del modelo mensual P.533.").font(.caption).foregroundStyle(.secondary)
            if !errors.isEmpty {
                Text("Fuentes sin actualizar: " + errors.keys.sorted().map { SpaceWeatherSource(rawValue: $0)?.title ?? "Copia local" }.joined(separator: ", ")).font(.caption).foregroundStyle(.orange)
            }
        }
    }
    private func scale(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    private func reading(_ title: String, value: SpaceReading?, age: Double, units: String, source: SpaceWeatherSource) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppLocalization.text(title)).font(.caption).foregroundStyle(.secondary)
            if let value { Text("\(value.value, specifier: "%.1f") \(units)").font(.title2.monospacedDigit()) }
            else { Text("Sin datos").font(.title2) }
            stamp(value?.observedAt, age: age, source: source)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func stamp(_ observed: Date?, age: Double, source: SpaceWeatherSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let observed {
                Text(observed.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!)) + " UTC").font(.caption2).monospacedDigit()
                if !(-300...age).contains(date.timeIntervalSince(observed)) { Text("Dato antiguo · conserva su fecha").font(.caption2).foregroundStyle(.orange) }
            }
            if errors[source.rawValue] != nil { Text("Consulta fallida · copia anterior").font(.caption2).foregroundStyle(.orange) }
            Link(source == .indices ? "ITU · fuente" : "NOAA · fuente", destination: source.url).font(.caption2)
        }.foregroundStyle(.secondary)
    }
}
