import SwiftUI
import MapKit
import RadioCore

struct ACARSMessagePanel: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MENSAJES ACARS · últimos 200").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Ejemplo ADS-C") { receiver.loadACARSApplicationExample() }.disabled(receiver.busy)
                Button("Exportar JSON…") { receiver.exportACARSJSON() }.disabled(receiver.acarsMessages.isEmpty)
            }
            if receiver.acarsMessages.isEmpty {
                Text("Los mensajes validados aparecerán aquí. ACARS necesita audio AM que conserve ambos tonos; usa Ejemplo para comprobar el motor.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Table(receiver.acarsMessages, selection: $receiver.selectedACARSMessage) {
                    TableColumn("Decodificado") { m in Text(m.decodedAt.formatted(date: .omitted, time: .standard)).monospacedDigit() }.width(90)
                    TableColumn("Matrícula") { m in Text(m.tail) }.width(90)
                    TableColumn("Vuelo") { m in Text(m.flight.isEmpty ? "—" : m.flight) }.width(75)
                    TableColumn("Etiqueta", value: \.label).width(65)
                    TableColumn("Mensaje") { m in Text(m.body.replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }
                }.frame(height: 180)
                if let message = receiver.acarsMessages.first(where: { $0.id == receiver.selectedACARSMessage }) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let pos = message.aircraftPosition {
                            Map { Marker(message.tail, systemImage: "airplane", coordinate: .init(latitude: pos.latitude, longitude: pos.longitude)) }
                                .frame(height: 180)
                            Text("Posición ADS-C recibida · \(pos.altitudeFeet) ft · no es seguimiento continuo").font(.caption)
                        }
                        if let application = message.applicationText {
                            ScrollView { Text(application).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 150)
                        }
                        Text("\(message.isDownlink ? "Aeronave → tierra" : "Tierra → aeronave") · Modo \(message.mode) · Bloque \(message.block) · Nº \(message.messageNumber.isEmpty ? "—" : message.messageNumber) · \(message.endBlock == 23 ? "continúa (ETB)" : "fin (ETX)")").font(.caption)
                        if let status = message.applicationStatus {
                            Text(status == 2 ? "Reensamblado pendiente: faltan bloques" : status == 5 ? "Fragmento fuera de secuencia: aplicación incompleta" : status == 1 ? "Aplicación reensamblada" : "Aplicación interpretada si el formato se reconoce").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Validado por acarsdec · \(message.parityCorrections) errores de paridad corregidos · \(message.levelDB, specifier: "%.1f") dB internos del motor").font(.caption).foregroundStyle(.secondary)
                        ScrollView { Text(message.body).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                            .frame(height: 110).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            HStack {
                Text("libacars interpreta ADS-C/CPDLC y reensambla bloques completos. Sin posición válida no se dibuja una aeronave. La hora es de decodificación.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link("acarsdec", destination: URL(string: "https://github.com/f00b4r0/acarsdec")!)
                Button("Licencia y fuentes") {
                    if let source = Bundle.main.url(forResource: "ACARS-Sources", withExtension: "tar.gz") { NSWorkspace.shared.activateFileViewerSelecting([source]) }
                }
            }.controlSize(.small)
        }
    }
}
