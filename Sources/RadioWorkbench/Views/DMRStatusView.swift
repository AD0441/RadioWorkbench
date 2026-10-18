import SwiftUI
import RadioCore

struct DMRStatusView: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        GroupBox("DMR · estado por intervalo") {
            VStack(alignment: .leading, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let recent = receiver.dmrStatus?.lastSyncAt.map { context.date.timeIntervalSince($0) < 3 } ?? false
                    Label(receiver.busy ? (recent ? "Sincronía observada recientemente" : "Buscando sincronía DMR") : "Sesión detenida · últimos datos", systemImage: recent && receiver.busy ? "waveform" : "antenna.radiowaves.left.and.right")
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(receiver.dmrStatus?.slots ?? DMRStatus().slots) { slot in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TS\(slot.slot)").fontWeight(.semibold)
                                Text("Código de color (CC): \(slot.colorCode.map(String.init) ?? "—")")
                                Text("Emisor: \(slot.sourceID.map(String.init) ?? "—")")
                                Text("Destino: \(slot.targetID.map(String.init) ?? "—")\(slot.callKind.map { " · " + $0 } ?? "")")
                                Text(slot.activity ?? "Sin datos del motor")
                                if let date = slot.identityAt {
                                    Text("Identidad observada hace \(max(0, Int(context.date.timeIntervalSince(date)))) s").foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if receiver.voiceFrames > 0 { Text("Audio de salida del motor: \(Double(receiver.voiceFrames) / 8000, specifier: "%.1f") s · estéreo") }
                if receiver.voiceOutputDropped > 0 { Text("Salida de voz saturada: \(receiver.voiceOutputDropped) muestras por canal descartadas. Reduce otras tareas o vuelve a procesar el WAV.").foregroundStyle(.orange) }
                Text("Datos interpretados de la consola DSD-neo 2.10.0. La hora corresponde al procesamiento; los campos ausentes quedan sin dato. No acredita CRC, identidad del emisor ni inteligibilidad de la voz. Las líneas con errores no sustituyen los identificadores anteriores.")
                    .foregroundStyle(.secondary)
                Button("Guardar estado DMR JSON…") { receiver.exportDMRStatus() }.disabled(receiver.dmrStatus?.lastSyncAt == nil)
            }.font(.caption).padding(5)
        }
    }
}
