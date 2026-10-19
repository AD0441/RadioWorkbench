import SwiftUI
import RadioCore

struct ReceiverView: View {
    @Bindable var receiver: ReceiverStore
    private var spectrum: some View {
        ReceiverSpectrumView(receiver: receiver)
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(receiver.mode.title).font(.largeTitle.weight(.semibold))
                    Text(receiver.mode.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Label(receiver.live ? "EN VIVO" : receiver.busy ? "PROCESANDO" : "LISTO", systemImage: receiver.live ? "record.circle" : "circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(receiver.live ? .red : .secondary)
                    .padding(8).background(.quaternary, in: Capsule())
            }
            AudioRoutingView(receiver: receiver)
            AdditionalEngineControls(receiver: receiver)
            DecoderControls(receiver: receiver)
            if receiver.mode == .acars {
                DisclosureGroup("Espectro y waterfall", isExpanded: $receiver.showsACARSSpectrum) { spectrum }
            } else { spectrum }
            HStack {
                Label(receiver.source, systemImage: receiver.live ? "mic" : "waveform")
                Spacer()
                ReceiverLevelView(visualization: receiver.visualization)
            }.font(.caption).foregroundStyle(.secondary)
            if receiver.busy && !receiver.live { ProgressView(value: receiver.progress) }
            Text(receiver.detail).font(.caption).foregroundStyle(.secondary)
            if let error = receiver.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if receiver.dropped > 0 { Text("Se perdieron \(receiver.dropped) muestras; se reinició la sincronización.").font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("TEXTO RECIBIDO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Volver a decodificar") { if let url = receiver.lastURL { receiver.decode(url) } }.disabled(receiver.busy || receiver.lastURL == nil)
                Button("Exportar…") { receiver.exportText() }.disabled(receiver.text.isEmpty)
            }
            if receiver.mode == .acars { ACARSMessagePanel(receiver: receiver) }
            else if receiver.mode == .ft8 || receiver.mode == .ft4 {
                VStack(alignment: .leading) {
                    HStack { Text("LDPC + CRC verificados · últimos 200").font(.caption); Spacer(); Button("Guardar JSON…") { receiver.exportEngineJSON() }.disabled(receiver.engineRecords.isEmpty) }
                    Table(receiver.engineRecords) {
                        TableColumn("Audio Hz") { Text($0.frequencyHz.map { String(format: "%.0f", $0) } ?? "—") }.width(85)
                        TableColumn("Inicio s") { Text($0.offsetSeconds.map { String(format: "%+.2f", $0) } ?? "—") }.width(75)
                        TableColumn("Sinc.") { Text($0.syncScore.map(String.init) ?? "—") }.width(65)
                        TableColumn("Mensaje", value: \.text)
                    }.frame(height: 200)
                }
            }
            else if receiver.mode.isMultimon {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(receiver.multimonRecords.count) registros visibles · retención máxima 200").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Guardar JSON…") { receiver.exportMultimonJSON() }.disabled(receiver.multimonRecords.isEmpty)
                    }
                    Table(receiver.multimonRecords) {
                        TableColumn("Formato", value: \.decoder)
                        TableColumn("Capcode") { record in Text(record.address.map(String.init) ?? "—") }
                        TableColumn("Función") { record in Text(record.function.map(String.init) ?? "—") }
                        TableColumn("Tipo", value: \.kind)
                        TableColumn("Contenido", value: \.body)
                    }.frame(minHeight: 200)
                }
            }
            else { ScrollView {
                Text(receiver.text.isEmpty ? "El texto decodificado aparecerá aquí." : receiver.text)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(receiver.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
            }.frame(height: 170).background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
            Text("Decodificadores experimentales: verifica la sintonía y contrasta señales difíciles. CWKit estima tono y velocidad; el motor Manual conserva sus ajustes. PSK31 requiere frecuencia estable.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        }
    }
}

struct DecoderControls: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            if receiver.mode != .dtmf && receiver.mode != .selectiveTones && receiver.mode != .acars && !receiver.mode.isMultimon && ![.ft8, .ft4, .digitalVoice, .ale, .gmdss].contains(receiver.mode) && !(receiver.mode == .morse && receiver.settings.cwEngine != .manual) {
                number("Audio (Hz)", value: $receiver.settings.frequency, width: 100)
            }
            if receiver.mode == .morse && receiver.settings.cwEngine == .manual { number("Velocidad (WPM)", value: $receiver.settings.wordsPerMinute, width: 100) }
            if [.rtty, .bitAnalysis].contains(receiver.mode) {
                number("Baud", value: $receiver.settings.baud, width: 85)
                number("Shift (Hz)", value: $receiver.settings.shift, width: 90)
                Toggle("Invertir", isOn: $receiver.settings.inverted).toggleStyle(.checkbox).padding(.bottom, 5)
            }
            if receiver.mode == .rtty {
                Picker("Código", selection: $receiver.settings.rttyEncoding) {
                    ForEach(RTTYEncoding.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 200)
            }
            if receiver.mode == .pocsag {
                Picker("Velocidad", selection: $receiver.settings.pagerRate) {
                    ForEach(PagerRate.allCases) { Text($0.title).tag($0) }
                }.frame(width: 235)
                Picker("BCH", selection: $receiver.settings.pagerCorrectionBits) {
                    ForEach(0...2, id: \.self) { Text("\($0) bits corregibles").tag($0) }
                }.frame(width: 165)
                Toggle("Avisos sin texto", isOn: $receiver.settings.pagerShowEmpty)
            }
            if receiver.mode == .fiveTones {
                Picker("Estándar", selection: $receiver.settings.fiveToneStandard) {
                    ForEach(FiveToneStandard.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 200)
                Text("E/F: códigos especiales sin reinterpretación").font(.caption).foregroundStyle(.secondary)
            }
            if receiver.mode == .psk31 { Text("BPSK · 31,25 baud").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5) }
            if receiver.mode == .packet { Text("AFSK · 1200 baud · AX.25 CRC").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5) }
            if receiver.mode == .acars { Text("MSK · 2400 baud · tonos fijos 1200/2400 Hz").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5) }
            if receiver.mode == .selectiveTones { Text("CTCSS · 51 tonos · búsqueda automática").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5) }
            if receiver.mode == .navtex {
                Text("100 baud · shift 170 Hz · FEC").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5)
                Toggle("Invertir", isOn: $receiver.settings.inverted).toggleStyle(.checkbox).padding(.bottom, 5)
            }
            Spacer(minLength: 0)
            if receiver.mode != .acars && !receiver.mode.isMultimon && ![.ft8, .ft4, .digitalVoice, .ale, .mt63, .gmdss].contains(receiver.mode) && !(receiver.mode == .morse && receiver.settings.cwEngine != .manual) { VStack(alignment: .leading, spacing: 6) {
                Text("Umbral \(Int(receiver.settings.threshold * 100)) %").font(.caption).foregroundStyle(.secondary)
                Slider(value: $receiver.settings.threshold, in: 0.01...0.5).frame(width: 150)
            } }
        }.disabled(receiver.busy)
    }
    private func number(_ title: String, value: Binding<Double>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: width)
        }
    }
}
