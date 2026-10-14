import SwiftUI
import Charts
import RadioCore

struct HFPredictionPanel: View {
    let report: HFPropagationReport
    let current: Bool
    let originCountry: String
    let targetCountry: String
    private var input: HFPropagationInput { report.input }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Predicción mensual del enlace").font(.title2.weight(.semibold))
            if !current { Label("Resultado anterior: cambió la configuración o la hora. Vuelve a calcular.", systemImage: "arrow.clockwise").foregroundStyle(.orange) }
            Text("\(input.watts, specifier: "%.0f") W · \(input.bandwidth, specifier: "%.0f") Hz · SNR requerido \(input.requiredSNR, specifier: "%.1f") dB · R12 \(input.r12.rounded(), specifier: "%.0f") · \(report.hourUTC):00 UTC · \(input.origin.distance(to: input.target), specifier: "%.0f") km · rumbo \(input.origin.bearing(to: input.target), specifier: "%.0f")°")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Label(RadioContactDistance.classify(km: input.origin.distance(to: input.target))?.rawValue ?? "Sin distancia", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                if let international = RadioContactDistance.international(originCountry: originCountry, targetCountry: targetCountry) {
                    Label(international ? "Internacional" : "Nacional", systemImage: international ? "globe" : "mappin")
                } else { Text("Países sin especificar").foregroundStyle(.secondary) }
                if let target = report.hourly.first(where: { $0.hour == report.hourUTC }), let bcr = target.reliability {
                    Text("Enlace objetivo: \(bcr >= 75 ? "favorable" : bcr >= 50 ? "regular" : "baja probabilidad") · \(percent(bcr)) BCR").foregroundStyle(bcr >= 75 ? .green : .orange)
                }
            }.font(.callout.weight(.medium))
            Text("Probabilidad estadística BCR de cumplir el SNR en ese mes y hora; no es una medición en vivo. La absorción reciente NOAA no se suma al modelo. Ganancias TX/RX: \(input.txGain, specifier: "%.1f") / \(input.rxGain, specifier: "%.1f") dBi; ruido RX: \(["ciudad", "residencial", "rural", "rural tranquilo"][input.noise]).").font(.caption).foregroundStyle(.secondary)
            Table(report.bands) {
                TableColumn("Banda") { row in Text(HFBand.all.first(where: { abs($0.frequencyMHz-row.frequencyMHz) < 0.001 })?.name ?? "HF") }.width(65)
                TableColumn("MHz") { row in Text(row.frequencyMHz.formatted(.number.precision(.fractionLength(1...2)))) }.width(70)
                TableColumn("BCR") { row in Text(percent(row.reliability)) }.width(90)
                TableColumn("SNR mediana") { row in Text(db(row.snrDB, units: "dB")) }.width(110)
                TableColumn("Potencia RX") { row in Text(db(row.receivedDBm, units: "dBm")) }.width(110)
                TableColumn("MUF50") { row in Text(db(row.muf50MHz, units: "MHz")) }
            }.frame(height: 295)
            Text("MUF50: frecuencia superada en el 50% de los días según el modelo; el motor no la devuelve para trayectos mayores de 9.000 km. No es la frecuencia recomendada de emisión.").font(.caption).foregroundStyle(.secondary)
            contactMatrix
            GroupBox("Horas UTC · \(input.frequencyMHz.formatted(.number.precision(.fractionLength(1...3)))) MHz") {
                Chart(report.hourly) { row in
                    if let bcr = row.reliability {
                        BarMark(x: .value("Hora UTC", row.hour), y: .value("BCR %", bcr))
                            .foregroundStyle(row.hour == report.hourUTC ? Color.accentColor : Color.secondary.opacity(0.35))
                    }
                }.chartYScale(domain: 0...100).chartXAxis { AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21, 23]) }
                    .chartYAxisLabel("BCR %").frame(height: 150).padding(10)
            }
            GroupBox("Alcance posible en el rumbo elegido · \(input.frequencyMHz.formatted(.number.precision(.fractionLength(1...3)))) MHz") {
                VStack(alignment: .leading, spacing: 8) {
                    Chart(report.reach) { row in
                        if let bcr = row.reliability {
                            PointMark(x: .value("Distancia km", row.distanceKm), y: .value("BCR %", bcr)).symbolSize(45)
                        }
                    }.chartYScale(domain: 0...100).chartYAxisLabel("BCR %").chartXAxisLabel("Distancia · km").frame(height: 170)
                    Text("15 distancias calculadas entre 100 y 18.000 km, a esta hora y hacia el mismo rumbo. Los puntos no definen un radio de cobertura: puede haber zonas de salto sin recepción entre enlaces posibles. Cambia los watts y vuelve a calcular para comparar.").font(.caption).foregroundStyle(.secondary)
                    if let delta = RadioLinkBudget.powerDifference(watts: input.watts, referenceWatts: 100) {
                        Text("Respecto a 100 W: \(delta, specifier: "%+.1f") dB de potencia TX. Duplicar potencia aporta aproximadamente 3 dB; no duplica la distancia.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(10)
            }
        }
    }
    private func percent(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(1))) + " %" } ?? "—" }
    private func db(_ value: Double?, units: String) -> String { value.map { $0.formatted(.number.precision(.fractionLength(1))) + " " + units } ?? "—" }
    private var contactMatrix: some View {
        GroupBox("Qué contactos podrían ser posibles · por banda y rumbo") {
            VStack(alignment: .leading, spacing: 8) {
                Table(HFBand.all) {
                    TableColumn("Banda", value: \.name).width(65)
                    TableColumn("Cercano") { band in contactCell(band, category: .nearby) }.width(min: 90, ideal: 140)
                    TableColumn("Regional") { band in contactCell(band, category: .regional) }.width(min: 90, ideal: 140)
                    TableColumn("Lejano") { band in contactCell(band, category: .distant) }.width(min: 90, ideal: 140)
                    TableColumn("DX lejano") { band in contactCell(band, category: .dx) }.width(min: 90, ideal: 140)
                }.frame(height: 310)
                Text("Mejor muestra BCR de cada intervalo, con tu potencia y el mismo rumbo TX→RX: cercano ≤100 km, regional 101–1.000 km, lejano 1.001–5.000 km, DX >5.000 km. Son etiquetas orientativas de la app. La muestra cercana es 100 km; P.533 calcula onda ionosférica, sin onda de tierra ni enlace directo. No describe todos los puntos intermedios ni prueba contactos reales.").font(.caption).foregroundStyle(.secondary)
                Text("Color del enlace: favorable ≥75 %, regular 50–74,9 %, baja <50 % BCR. Internacional/nacional depende de los países que hayas indicado, y puede coincidir con cualquier distancia.").font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
    private func contactCell(_ band: HFBand, category: RadioContactDistance) -> some View {
        let best = report.contactSamples(frequencyMHz: band.frequencyMHz, category: category).filter { $0.reliability != nil }.max { ($0.reliability ?? 0) < ($1.reliability ?? 0) }
        return VStack(alignment: .leading, spacing: 2) {
            if let best, let bcr = best.reliability {
                Text(percent(bcr)).foregroundStyle(bcr >= 75 ? Color.green : bcr >= 50 ? Color.orange : Color.secondary)
                Text("a \(best.distanceKm, specifier: "%.0f") km").foregroundStyle(.secondary)
            } else { Text("Sin cálculo").foregroundStyle(.secondary) }
        }.font(.caption).monospacedDigit()
    }
}
