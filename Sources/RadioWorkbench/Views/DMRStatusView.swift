import SwiftUI
import RadioCore

struct DMRStatusView: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        GroupBox("Actividad DMR") {
            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let recent = receiver.dmrStatus?.lastSyncAt.map { isRecent($0, at: context.date) } ?? false
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Entrada").foregroundStyle(.secondary)
                            Label(receiver.busy ? (receiver.live ? (receiver.samplesReceived > 0 ? "Muestras recibidas" : "Esperando muestras") : "Archivo en proceso") : "Sesión detenida",
                                  systemImage: receiver.busy && receiver.samplesReceived > 0 ? "waveform" : "pause.circle")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sincronía del motor").foregroundStyle(.secondary)
                            Label(receiver.busy ? (recent ? "Observada hace menos de 3 s" : "Buscando DMR") : "Últimos datos de la sesión",
                                  systemImage: recent && receiver.busy ? "antenna.radiowaves.left.and.right" : "clock")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(receiver.dmrStatus?.slots ?? DMRStatus().slots) { slot in
                            DMRSlotCard(slot: slot, now: context.date, running: receiver.busy)
                        }
                    }
                }
                HStack {
                    Text("La selección de voz \(receiver.settings.dmrSlotSelection.title) no filtra los datos de llamada visibles.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Guardar estado JSON…") { receiver.exportDMRStatus() }.disabled(receiver.dmrStatus?.lastSyncAt == nil)
                }
                DisclosureGroup("Procedencia de los datos de llamada") {
                    Text("Consola DSD-neo 2.10.0. Las horas corresponden al procesamiento; los identificadores conservan su propia antigüedad. Los campos ausentes quedan sin dato y las líneas con errores no sustituyen identidades anteriores. La consola no acredita CRC, identidad del emisor ni inteligibilidad de la voz.")
                        .foregroundStyle(.secondary).padding(.top, 4)
                }
            }.font(.caption).padding(6)
        }
    }
    private func isRecent(_ date: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < 3
    }
}

private struct DMRSlotCard: View {
    let slot: DMRSlotStatus
    let now: Date
    let running: Bool
    private var recent: Bool {
        guard running, let date = slot.updatedAt else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < 3
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("TS\(slot.slot)").font(.headline)
                Spacer()
                Text(recent ? "RECIENTE" : slot.updatedAt == nil ? "SIN DATOS" : "ANTERIOR")
                    .font(.caption2.weight(.semibold)).foregroundStyle(recent ? .green : .secondary)
            }
            LabeledContent("Código de color", value: slot.colorCode.map(String.init) ?? "—")
            LabeledContent("Origen", value: slot.sourceID.map(String.init) ?? "—")
            LabeledContent("Destino", value: slot.targetID.map(String.init) ?? "—")
            LabeledContent("Clase", value: slot.callKind ?? "—")
            Text(slot.activity ?? "Sin actividad interpretada").foregroundStyle(.secondary)
            if let date = slot.updatedAt { Text("Actividad: hace \(max(0, Int(now.timeIntervalSince(date)))) s").foregroundStyle(.secondary) }
            if let date = slot.identityAt { Text("Identidades: hace \(max(0, Int(now.timeIntervalSince(date)))) s").foregroundStyle(.secondary) }
        }.monospacedDigit().padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
