import SwiftUI
import RadioCore

struct AdditionalEngineControls: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        if receiver.mode == .morse {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Motor CW", selection: $receiver.settings.cwEngine) {
                    ForEach(CWEngine.allCases) { engine in Text(engine.rawValue).tag(engine).disabled(engine != .manual && !CWEngine.isSupported) }
                }.frame(width: 320).disabled(receiver.busy)
                Text("CWKit: tono y WPM automáticos, macOS 15+. Neuronal usa un modelo Core ML en CPU, con varios segundos de latencia. Verifica indicativos con señales difíciles.").font(.caption).foregroundStyle(.secondary)
                if receiver.settings.cwEngine == .neural, let tentative = receiver.engineRecords.last?.tentative, !tentative.isEmpty {
                    Text("Provisional: " + tentative).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        if receiver.mode == .ft8 || receiver.mode == .ft4 {
            HStack {
                Text("Inicio de primera ventana WAV (s)").font(.caption)
                TextField("Segundos", value: $receiver.settings.ftxStartSeconds, format: .number).textFieldStyle(.roundedBorder).frame(width: 90).disabled(receiver.busy)
                Text("En vivo: espera al siguiente límite UTC. SNR no estimado.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if receiver.mode == .digitalVoice {
            GroupBox("DSD-neo · recepción de un canal") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Protocolo", selection: $receiver.settings.digitalVoiceProtocol) { ForEach(DigitalVoiceProtocol.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 300).disabled(receiver.busy)
                    if ExternalAudioEngine.dsdInstalledURL == nil {
                        Button(receiver.engineDownloading ? "Descargando…" : "Descargar motor oficial arm64 (9 MB)") { receiver.installDSD() }
                            .disabled(receiver.engineDownloading || receiver.busy || !ExternalAudioEngine.dsdSupported)
                    } else { Label("DSD-neo 2.10.0 instalado", systemImage: "checkmark.circle") }
                    Text("El paquete oficial requiere macOS 26. Se descarga desde GitHub y se verifica SHA-256. Solo audio del canal seleccionado; sin control del SDR ni claves de cifrado.").font(.caption).foregroundStyle(.secondary)
                    if !receiver.engineNotice.isEmpty { Text(receiver.engineNotice).font(.caption).textSelection(.enabled) }
                    HStack {
                        Button("Reproducir voz") { receiver.playVoice() }.disabled(receiver.busy || receiver.voiceFinalizing || receiver.voiceURL == nil)
                        Button("Guardar voz WAV…") { receiver.exportVoice() }.disabled(receiver.busy || receiver.voiceFinalizing || receiver.voiceURL == nil)
                        Text("Disponible al terminar o detener. Máximo 30 min por sesión.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(5)
            }
        }
    }
}
