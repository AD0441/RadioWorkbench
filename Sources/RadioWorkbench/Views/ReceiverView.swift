import SwiftUI
import RadioCore

struct ReceiverView: View {
    @Bindable var receiver: ReceiverStore
    private var spectrum: some View {
        SpectrumView(frame: receiver.frame, waterfall: receiver.waterfall, frequency: receiver.settings.frequency, shift: receiver.mode == .navtex ? 170 : receiver.mode == .rtty ? receiver.settings.shift : 0) { value in
            if !receiver.busy && receiver.mode != .selectiveTones && receiver.mode != .acars { receiver.settings.frequency = value }
        }
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
            DecoderControls(receiver: receiver)
            if receiver.mode == .acars {
                DisclosureGroup("Espectro y waterfall", isExpanded: $receiver.showsACARSSpectrum) { spectrum }
            } else { spectrum }
            HStack {
                Label(receiver.source, systemImage: receiver.live ? "mic" : "waveform")
                Spacer()
                if let frame = receiver.frame {
                    Text("\(frame.levelDB, specifier: "%.1f") dBFS").monospacedDigit()
                    if frame.clipped { Label("Saturación", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
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
            else { ScrollView {
                Text(receiver.text.isEmpty ? "El texto decodificado aparecerá aquí." : receiver.text)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(receiver.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
            }.frame(height: 170).background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
            Text("Decodificadores experimentales: verifica la sintonía y contrasta señales difíciles. La tasa de CW es manual; PSK31 requiere frecuencia estable.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        }
    }
}

struct DecoderControls: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            if receiver.mode != .dtmf && receiver.mode != .selectiveTones && receiver.mode != .acars {
                number("Audio (Hz)", value: $receiver.settings.frequency, width: 100)
            }
            if receiver.mode == .morse { number("Velocidad (WPM)", value: $receiver.settings.wordsPerMinute, width: 100) }
            if [.rtty, .bitAnalysis].contains(receiver.mode) {
                number("Baud", value: $receiver.settings.baud, width: 85)
                number("Shift (Hz)", value: $receiver.settings.shift, width: 90)
                Toggle("Invertir", isOn: $receiver.settings.inverted).toggleStyle(.checkbox).padding(.bottom, 5)
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
            if receiver.mode != .acars { VStack(alignment: .leading, spacing: 6) {
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
