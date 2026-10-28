import SwiftUI
import RadioCore

private struct IonosondeDisplayRow: Identifiable {
    let observation: IonosondeObservation
    let distanceKm: Double
    var id: String { observation.id }
}

struct IonosondePanel: View {
    let snapshot: IonosondeSnapshot?
    let status: String
    let location: RadioLocation?
    let date: Date

    var body: some View {
        GroupBox("Ionosondas cercanas · observación regional") {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.text(status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let location, let snapshot {
                    let nearby = snapshot.nearest(to: location, limit: 5)
                    if nearby.isEmpty {
                        Text("No hay estaciones con datos válidos en la copia disponible.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        let rows = nearby.map { IonosondeDisplayRow(observation: $0.0, distanceKm: $0.1) }
                        Table(rows) {
                            TableColumn("Estación") { item in Text("\(item.observation.name) · \(item.observation.code)") }.width(min: 160, ideal: 220)
                            TableColumn("Distancia") { item in Text("\(item.distanceKm, specifier: "%.0f") km").monospacedDigit() }.width(85)
                            TableColumn("foF2") { item in Text(item.observation.fof2MHz.map { "\($0, specifier: "%.1f") MHz" } ?? "—") }.width(80)
                            TableColumn("MUF · 3000 km") { item in Text(item.observation.muf3000MHz.map { "\($0, specifier: "%.1f") MHz" } ?? "—") }.width(115)
                            TableColumn("Confianza") { item in Text(AppLocalization.text(confidence(item.observation.confidence))) }.width(105)
                            TableColumn("Observación UTC") { item in Text(item.observation.observedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!))) }.width(155)
                        }.frame(minHeight: 110, maxHeight: 220)
                        if let nearest = nearby.first, nearest.1 > 3_000 {
                            Label("La estación más cercana está a más de 3.000 km; úsala solo como contexto regional amplio.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if nearby.contains(where: { date.timeIntervalSince($0.0.observedAt) > 2 * 3600 }) {
                            Text("Algunas observaciones superan 2 horas de antigüedad; mira la hora de cada estación antes de interpretarlas.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                } else if location == nil {
                    Text("Introduce una ubicación para ordenar las estaciones por distancia. La consulta de datos no transmite tus coordenadas.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Sin observaciones ionosféricas cargadas. Actualizar vuelve a consultar la fuente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Son mediciones de estaciones ionosonda, no una medición de propagación en tu casa. Distancia, antigüedad y confianza ayudan a juzgar cuánto contexto aportan; la cobertura de estaciones es desigual.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Link("Mapa y API KC2G", destination: URL(string: "https://prop.kc2g.com/about/")!)
                    Link("GIRO · condiciones de uso CC BY-NC-SA 4.0", destination: URL(string: "https://giro.uml.edu/didbase/RulesOfTheRoad.html")!)
                    Spacer()
                }.font(.caption2)
                Text("Atribución: datos GIRO y operadores de las estaciones; representación/API de Andrew Rodland (KC2G), prop.kc2g.com. Uso de datos sujeto a CC BY-NC-SA 4.0.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(7)
        }
    }

    private func confidence(_ value: Double?) -> String {
        guard let value else { return "No informado" }
        return value < 0 ? "No calculada" : String(format: "%.0f %%", value)
    }
}
