import SwiftUI
import RadioCore

struct NoaaThreeDayForecastPanel: View {
    let forecast: NoaaThreeDayForecast?
    let status: String

    var body: some View {
        GroupBox("Pronóstico NOAA SWPC · próximos tres días") {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.text(status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let forecast {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(forecast.datesUTC.enumerated()), id: \.offset) { index, date in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "es_CL"), timeZone: TimeZone(secondsFromGMT: 0)!)))
                                    .font(.headline)
                                Label("Kp máx. \(forecast.dailyMaximumKp.indices.contains(index) ? forecast.dailyMaximumKp[index].formatted(.number.precision(.fractionLength(0...2))) : "—")", systemImage: "globe.americas")
                                Text("Tormenta solar S1+: \(forecast.s1OrGreaterProbability.indices.contains(index) ? forecast.s1OrGreaterProbability[index] : 0)%")
                                Text("Apagón R1–R2: \(forecast.r1ToR2Probability.indices.contains(index) ? forecast.r1ToR2Probability[index] : 0)%")
                                Text("Apagón R3+: \(forecast.r3OrGreaterProbability.indices.contains(index) ? forecast.r3OrGreaterProbability[index] : 0)%")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    if !forecast.geomagneticRationale.isEmpty {
                        Label("Geomagnética: \(forecast.geomagneticRationale)", systemImage: "globe")
                            .font(.caption).textSelection(.enabled)
                    }
                    if !forecast.blackoutRationale.isEmpty {
                        Label("Radio HF: \(forecast.blackoutRationale)", systemImage: "waveform.path")
                            .font(.caption).textSelection(.enabled)
                    }
                    Text("Kp resume actividad geomagnética; R estima probabilidad de apagón de radio por fulguraciones y S tormenta de radiación. Son previsiones NOAA, no disponibilidad asegurada de una banda ni alcance local.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Sin pronóstico", systemImage: "sun.max.trianglebadge.exclamationmark", description: Text("Con conexión, pulsa Actualizar para consultar el texto oficial de NOAA SWPC."))
                }
                Link("NOAA SWPC · pronóstico de tres días", destination: URL(string: "https://www.swpc.noaa.gov/products/3-day-forecast")!).font(.caption)
            }.padding(7)
        }
    }
}
