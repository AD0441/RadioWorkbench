import AppKit
import SwiftUI
import RadioCore
import UniformTypeIdentifiers

struct InputConnectionAssistant: View {
    @Bindable var receiver: ReceiverStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var step = 1
    @ViewState private var notice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Asistente de conexión").font(.title2.weight(.semibold))
            Picker("Paso", selection: $step) {
                Text("1 · Fuente y parámetros").tag(1)
                Text("2 · Nivel y continuidad").tag(2)
                Text("3 · Decodificación").tag(3)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if step == 1 {
                        Text("\(receiver.mode.title) · \(receiver.inputSource.rawValue)").font(.headline)
                        Text(receiver.inputSource == .tcp ? "TCP local · \(receiver.networkPCM.sampleRate.formatted()) Hz · \(receiver.networkPCM.channels) canales" : receiver.selectedInput?.name ?? "Entrada predeterminada del sistema")
                        Text("Canal: \(receiver.settings.audioChannel.label)")
                        let profile = receiver.mode.receptionProfile(settings: receiver.settings)
                        Text("SDR: \(profile.modulation.rawValue) · filtro RF inicial \(profile.rfBandwidth.formatted()) Hz")
                        Text(profile.audioBand); Text(profile.note).foregroundStyle(.secondary)
                        Text("Configura esos valores en SDR++. Para una salida de discriminador, conserva subaudio y niveles; los filtros de voz pueden eliminar datos. Comprueba que la salida llegue al dispositivo seleccionado aquí.").font(.callout)
                    } else if step == 2 {
                        if receiver.busy { Button("Detener entrada") { receiver.stop() } }
                        else { Button("Escuchar con la entrada seleccionada") { receiver.startLive() }.buttonStyle(.borderedProminent) }
                        Text("Activa la entrada y envía una señal de prueba completa. Observa también las pausas: un bloque silencioso no demuestra un fallo de conexión.").foregroundStyle(.secondary)
                        InputQualityView(receiver: receiver)
                        Text("Muestras recibidas: \(receiver.samplesReceived) · descartadas: \(receiver.dropped)").monospacedDigit()
                        if receiver.captureSampleRate > 0 { Text("Tasa efectiva: \(receiver.captureSampleRate.formatted()) Hz") }
                    } else {
                        if let metrics = receiver.integrity {
                            Text(metrics.check).font(.headline)
                            Text("\(metrics.accepted) \(metrics.unit) aceptados" + (metrics.rejected.map { " · \($0) rechazados" } ?? ""))
                            Text(metrics.note).foregroundStyle(.secondary)
                        } else {
                            Text(receiver.detail).textSelection(.enabled)
                            Text("Este motor no expone todos los contadores. Comprueba su resultado y los avisos de integridad; no se calcula un porcentaje de éxito a partir del aspecto del espectro.").foregroundStyle(.secondary)
                        }
                        Text("Si no adquiere: verifica modo, centro y ancho de audio, canal, inversión y cabecera completa. Prueba el ejemplo incluido para separar un problema de entrada de uno del decodificador.")
                        Button("Guardar diagnóstico local…") { exportDiagnostic() }
                    }
                    if let error = receiver.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Anterior") { step -= 1 }.disabled(step == 1)
                Button("Siguiente") { step += 1 }.disabled(step == 3)
                Spacer(); Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 700, height: 500)
    }
    private func exportDiagnostic() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "diagnostico-entrada.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var report: [String: Any] = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "mode": receiver.mode.rawValue, "sampleRate": receiver.captureSampleRate, "received": receiver.samplesReceived,
            "dropped": receiver.dropped, "channel": receiver.settings.audioChannel.label,
            "note": "Local input measurements; no audio, decoded messages, station location or calibrated RF SNR."]
        if let frame = receiver.frame {
            report["lastAnalyzedBlock"] = ["sampleRate": frame.sampleRate, "samples": frame.quality.sampleCount,
                "rmsDBFS": frame.levelDB, "clippedSamples": frame.quality.clippedCount, "invalidSamples": frame.quality.invalidCount, "dc": frame.quality.dc]
        }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic); notice = "Diagnóstico guardado; no contiene audio ni texto recibido." }
        catch { notice = error.localizedDescription }
    }
}
