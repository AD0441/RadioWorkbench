import SwiftUI
import RadioCore

struct AdditionalEngineControls: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        if receiver.mode == .gmdss {
            GroupBox("DSC · recepción experimental") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Variante", selection: $receiver.settings.dscVariant) {
                        ForEach(DSCVariant.allCases) { Text($0.title).tag($0) }
                    }.frame(width: 390).disabled(receiver.busy)
                        .onChange(of: receiver.settings.dscVariant) { receiver.applyDSCVariant() }
                    if receiver.settings.dscVariant == .mfHF {
                        HStack {
                            Text("Centro de audio Hz")
                            TextField("Hz", value: $receiver.settings.frequency, format: .number).frame(width: 100).textFieldStyle(.roundedBorder)
                        }.disabled(receiver.busy)
                    } else {
                        Toggle("El audio ya tiene de-emphasis aplicado", isOn: $receiver.settings.dscDeemphasized).disabled(receiver.busy)
                    }
                    Toggle("Invertir polaridad", isOn: $receiver.settings.inverted).disabled(receiver.busy)
                    Text(receiver.settings.dscVariant == .mfHF ? "MF/HF: USB, 100 baud, shift 170 Hz; ajusta el centro al audio recibido. En LSB puede ser necesario invertir." : "VHF: NFM, filtro RF 16 kHz, tonos 1300/2100 Hz; conserva la ráfaga completa y deja squelch abierto. Entrada recomendada: discriminador sin de-emphasis.")
                    Text("Se aceptan tramas completas con ECC válido y diversidad temporal. Se muestran identidades, símbolos y algunos canales; la interpretación es parcial. ECC no autentica al emisor. No genera avisos de rescate ni transmite.")
                        .foregroundStyle(.secondary)
                    if let record = receiver.engineRecords.last {
                        Text("Origen: \(record.origin ?? "—") · destino: \(record.destination ?? "—") · ECC \(record.eccValid == true ? "válido" : "no confirmado")")
                        if let channel = record.rxChannel { Text("Canal de trabajo RX: \(channel) · TX: \(record.txChannel.map(String.init) ?? "—")") }
                    }
                    Button("Guardar mensajes y símbolos JSON…") { receiver.exportEngineJSON() }.disabled(receiver.engineRecords.isEmpty)
                }.font(.caption).padding(6)
            }
        }
        if receiver.mode == .mt63 {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Variante MT63", selection: $receiver.settings.mt63Variant) {
                    ForEach(MT63Variant.allCases) { Text($0.title).tag($0) }
                }.frame(width: 370).disabled(receiver.busy)
                    .onChange(of: receiver.settings.mt63Variant) { receiver.applyMT63Variant() }
                Text("Banda de audio: \(receiver.settings.frequency - Double(receiver.settings.mt63Variant.bandwidth) / 2, specifier: "%.0f")–\(receiver.settings.frequency + Double(receiver.settings.mt63Variant.bandwidth) / 2, specifier: "%.0f") Hz")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Selecciona el mismo ancho y entrelazado del emisor. Audio (Hz) indica el centro. La adquisición y el entrelazado pueden tardar más de 20 s en 500 Hz/largo; las emisiones cortas pueden perder el inicio. Recepción experimental, sin CRC de mensaje.")
                    .font(.caption).foregroundStyle(.secondary)
                    .onChange(of: receiver.settings.frequency) { receiver.updateMT63Bandwidth() }
                Button("Guardar registros JSON…") { receiver.exportEngineJSON() }.disabled(receiver.engineRecords.isEmpty)
            }
        }
        if receiver.mode == .ale {
            VStack(alignment: .leading, spacing: 6) {
                Text("ALE 2G · 8-FSK · 125 símbolos/s · Golay y diversidad temporal").font(.caption)
                Text("Sintoniza en SDR++ para conservar 750–2500 Hz. Muestra sondeos, llamadas y mensajes AMD; no transmite ni explora frecuencias automáticamente. ALE 3G sigue pendiente.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Guardar registros JSON…") { receiver.exportEngineJSON() }.disabled(receiver.engineRecords.isEmpty)
            }
        }
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
