import SwiftUI
import RadioCore

/// The discriminator input, protocol activity and decoded voice are separate
/// stages. The spectrum remains in its own observation scope at live frame rate.
struct DigitalVoiceView: View {
    @Bindable var receiver: ReceiverStore
    @ViewState private var showsSpectrum = false
    @ViewState private var showsLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if ExternalAudioEngine.dsdInstalledURL == nil {
                    HStack {
                        Label(ExternalAudioEngine.dsdSupported ? "Instala el motor para recibir voz digital." : "DSD-neo oficial requiere macOS 26.", systemImage: "shippingbox")
                        Spacer()
                        Button(receiver.engineDownloading ? "Descargando…" : "Descargar motor oficial") { receiver.installDSD() }
                            .disabled(receiver.engineDownloading || receiver.busy || !ExternalAudioEngine.dsdSupported)
                    }.font(.caption)
                    if !receiver.engineNotice.isEmpty { Text(receiver.engineNotice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                DigitalVoiceInputView(receiver: receiver)
                DigitalVoicePreparationView(receiver: receiver)
                if receiver.settings.digitalVoiceProtocol == .dmr {
                    DMRStatusView(receiver: receiver)
                } else {
                    GroupBox("Actividad · " + receiver.settings.digitalVoiceProtocol.rawValue) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(receiver.busy ? "Procesando el canal seleccionado" : "Preparado para recibir", systemImage: "antenna.radiowaves.left.and.right")
                            Text("La sincronía, las identidades y el tipo de trama de este protocolo se consultan en el registro del decodificador.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
                DigitalVoiceOutputView(receiver: receiver)
                if receiver.busy && !receiver.live { ProgressView(value: receiver.progress) }
                Text(receiver.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let error = receiver.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                }
                if receiver.dropped > 0 {
                    Text("Entrada: \(receiver.dropped) muestras descartadas; se reinició la sincronización.").font(.caption).foregroundStyle(.orange)
                }
                DisclosureGroup("Espectro y waterfall de audio", isExpanded: $showsSpectrum) {
                    VStack(alignment: .leading, spacing: 6) {
                        ReceiverSpectrumView(receiver: receiver)
                        Text("Audio de discriminador. La frecuencia del canal se ajusta en el SDR; este gráfico no sintoniza un tono DSD.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
                InputQualityView(receiver: receiver)
                DisclosureGroup("Registro del decodificador", isExpanded: $showsLog) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Consola DSD-neo · últimos 40.000 caracteres").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Exportar registro…") { receiver.exportText() }.disabled(receiver.text.isEmpty)
                        }
                        ScrollView {
                            Text(receiver.text.isEmpty ? "Las líneas del motor aparecerán aquí al procesar audio." : receiver.text)
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                        }.frame(height: 210).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }.padding(.top, 8)
                }
                DisclosureGroup("Motor, ejemplo y límites de recepción") {
                    DigitalVoiceEngineDetails(receiver: receiver).padding(.top, 8)
                }
            }.padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voz digital").font(.largeTitle.weight(.semibold))
                    Text("Un canal RF · entrada de discriminador · DSD-neo").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Label(receiver.live ? "EN VIVO" : receiver.busy ? "ARCHIVO EN PROCESO" : "DETENIDO", systemImage: receiver.live ? "record.circle" : "circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(receiver.live ? .red : .secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { protocolPicker; Spacer(minLength: 8); transportButtons }
                VStack(alignment: .leading, spacing: 8) { protocolPicker; transportButtons }
            }
            HStack {
                Label(receiver.source, systemImage: receiver.inputSource == .tcp && receiver.live ? "network" : "waveform")
                Spacer()
                ReceiverLevelView(visualization: receiver.visualization)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var protocolPicker: some View {
        Picker("Protocolo", selection: $receiver.settings.digitalVoiceProtocol) {
            ForEach(DigitalVoiceProtocol.allCases) { Text($0.rawValue).tag($0) }
        }.frame(width: 280).disabled(receiver.busy)
    }
    private var transportButtons: some View {
        HStack {
            Button("Abrir audio…", systemImage: "folder") { receiver.openAudio() }.disabled(receiver.busy)
            Button("Escuchar", systemImage: "mic") { receiver.startLive() }.disabled(receiver.busy)
            Button("Detener", systemImage: "stop.fill") { receiver.stop() }.disabled(!receiver.busy)
        }
    }
}

private struct DigitalVoiceInputView: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        GroupBox("Entrada de audio") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Fuente", selection: $receiver.inputSource) {
                        ForEach(ReceiverInputSource.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 340).disabled(receiver.busy)
                        .onChange(of: receiver.inputSource) { receiver.inputSelectionChanged() }
                    Spacer()
                }
                if receiver.inputSource == .tcp { TCPAudioControls(receiver: receiver) }
                else {
                    HStack {
                        Picker("Dispositivo", selection: $receiver.selectedDeviceID) {
                            Text("Predeterminada del sistema").tag(UInt32(0))
                            ForEach(receiver.devices) { device in
                                Text("\(device.name) · \(Int(device.sampleRate)) Hz · \(device.channels) ch").tag(device.id)
                            }
                        }.frame(maxWidth: 540)
                            .onChange(of: receiver.selectedDeviceID) { receiver.inputSelectionChanged() }
                        Button("Actualizar", systemImage: "arrow.clockwise") { receiver.refreshDevices() }
                    }.disabled(receiver.busy)
                }
                Picker("Canal que contiene el discriminador", selection: $receiver.settings.audioChannel) {
                    Text("Mezclar canales a mono").tag(AudioChannelSelection.mix)
                    ForEach(0..<receiver.availableChannelCount, id: \.self) { index in
                        Text(AudioChannelSelection.channel(index).label).tag(AudioChannelSelection.channel(index))
                    }
                }.id(receiver.settings.audioChannel).frame(maxWidth: 440).disabled(receiver.busy)
                if receiver.captureSampleRate > 0 {
                    Text("Última captura: \(Int(receiver.captureSampleRate)) Hz · \(receiver.sourceChannelCount) canal(es). El motor recibe PCM mono remuestreado a 48 kHz.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Perfiles guardados de entrada") { InputProfilesView(receiver: receiver).padding(.top, 6) }
            }.padding(6)
        }
    }
}

private struct DigitalVoicePreparationView: View {
    @Bindable var receiver: ReceiverStore
    private var preset: DigitalVoiceReceptionPreset { receiver.settings.digitalVoiceProtocol.receptionPreset }
    var body: some View {
        GroupBox("Preparar SDR++ / Brown") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sugerido: NFM · filtro RF \(preset.rfBandwidthHz.formatted()) Hz").fontWeight(.medium)
                    Spacer()
                    Button("Aplicar guía RF") { receiver.applyDigitalVoicePreset() }.disabled(receiver.busy)
                }
                Text(preset.audioDescription).font(.caption).foregroundStyle(.secondary)
                if receiver.settings.digitalVoiceProtocol == .dmr {
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack { slotPicker; monitorToggle }
                        VStack(alignment: .leading, spacing: 7) { slotPicker; monitorToggle }
                    }.disabled(receiver.busy)
                    Text("Elige antes de iniciar. Con monitor activo, la voz usa la salida del sistema y los archivos avanzan a velocidad de reproducción.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Detalles de RF, formato y conexión") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preset.signalModulation)
                        Text(preset.note).foregroundStyle(.secondary)
                        HStack {
                            Picker("Guía de sintonía", selection: $receiver.rfModulation) {
                                ForEach(RFModulation.allCases.filter { $0 != .iq }) { Text($0.rawValue).tag($0) }
                            }.frame(width: 205)
                            Text("Filtro RF")
                            TextField("Hz", value: $receiver.rfBandwidth, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 95)
                            Text("Hz")
                        }.disabled(receiver.busy)
                        Text("Ajusta esos valores manualmente en el SDR. Desactiva de-emphasis, squelch, pasa-altos, reducción de ruido y filtros de voz. La voz ya decodificada y el I/Q no son esta entrada PCM.")
                            .foregroundStyle(.secondary)
                        if receiver.inputSource == .tcp {
                            Text("Brown → Network Sink TCP: el formato, la tasa y los canales de ambos extremos deben coincidir. Aplicar la guía RF no modifica esa conexión.")
                                .foregroundStyle(.secondary)
                        }
                        if receiver.settings.digitalVoiceProtocol == .dmr {
                            Text("Los canales izquierdo/derecho de salida no identifican TS1/TS2.").foregroundStyle(.secondary)
                        }
                        Link(preset.sourceTitle, destination: preset.sourceURL)
                    }.font(.caption).padding(.top, 6)
                }
            }.padding(6)
        }
    }
    private var slotPicker: some View {
        Picker("Escuchar intervalo", selection: $receiver.settings.dmrSlotSelection) {
            ForEach(DMRSlotSelection.allCases) { Text($0.title).tag($0) }
        }.frame(width: 320)
    }
    private var monitorToggle: some View {
        Toggle("Escuchar voz en vivo", isOn: $receiver.settings.dmrMonitorVoice)
    }
}

private struct DigitalVoiceOutputView: View {
    @Bindable var receiver: ReceiverStore
    private var outputState: String {
        if receiver.voiceFinalizing { return "Finalizando el archivo WAV…" }
        if receiver.busy { return "El WAV se podrá revisar al detener o terminar." }
        if receiver.voiceURL != nil { return "WAV finalizado · \(receiver.voiceProtocol?.rawValue ?? "protocolo sin dato") · comprueba la voz al reproducirlo." }
        return "Todavía no hay un WAV de esta sesión."
    }
    var body: some View {
        GroupBox("Salida de voz") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(outputState, systemImage: receiver.voiceFinalizing ? "hourglass" : "speaker.wave.2")
                    if receiver.voiceFinalizing { ProgressView().controlSize(.small) }
                    Spacer()
                }
                HStack {
                    Button("Reproducir WAV", systemImage: "play.fill") { receiver.playVoice() }
                    Button("Guardar voz WAV…", systemImage: "square.and.arrow.up") { receiver.exportVoice() }
                }.disabled(receiver.busy || receiver.voiceFinalizing || receiver.voiceURL == nil)
                if receiver.settings.digitalVoiceProtocol == .dmr {
                    if receiver.busy && receiver.settings.dmrMonitorVoice {
                        Text("Monitor de voz habilitado · \(Double(receiver.voiceFrames) / 8000, specifier: "%.1f") s de PCM observados del motor.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if receiver.busy {
                        Text("Monitor de voz desactivado. Se conserva la salida WAV del motor para revisar al terminar.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(receiver.settings.dmrMonitorVoice ? "El monitor de voz está preparado para la próxima recepción." : "La próxima recepción guardará WAV, con el monitor de voz desactivado.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if receiver.voiceOutputDropped > 0 {
                    Text("Salida saturada: \(receiver.voiceOutputDropped) muestras por canal descartadas del monitor. Puedes revisar el WAV al terminar.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Máximo 30 minutos por sesión. Audio entrante, sincronía y datos de llamada no garantizan voz inteligible; un WAV puede contener silencio.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}

private struct DigitalVoiceEngineDetails: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ExternalAudioEngine.dsdInstalledURL == nil {
                Button(receiver.engineDownloading ? "Descargando…" : "Descargar DSD-neo oficial arm64 (9 MB)") { receiver.installDSD() }
                    .disabled(receiver.engineDownloading || receiver.busy || !ExternalAudioEngine.dsdSupported)
            } else { Label("DSD-neo 2.10.0 instalado", systemImage: "checkmark.circle") }
            if !ExternalAudioEngine.dsdSupported { Text("El motor oficial requiere macOS 26.").foregroundStyle(.orange) }
            if !receiver.engineNotice.isEmpty { Text(receiver.engineNotice).textSelection(.enabled) }
            Text("Descarga oficial con SHA-256 verificado. Recepción del canal seleccionado, sin seguimiento de trunking ni gestión de claves. No todos los protocolos exponen los mismos campos en esta interfaz.")
                .foregroundStyle(.secondary)
            Button("Ejemplo M17 de datos…") { receiver.loadExample() }.disabled(receiver.busy)
            Text("El ejemplo es una señal sintética M17 de paquetes. Se confirma el cambio de protocolo antes de abrirlo; no comprueba voz DMR.")
                .foregroundStyle(.secondary)
            if let _ = receiver.lastURL {
                Button("Volver a procesar este archivo") { if let url = receiver.lastURL { receiver.decode(url) } }.disabled(receiver.busy)
            }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
}
