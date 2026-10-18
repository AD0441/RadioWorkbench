import SwiftUI
import RadioCore

struct ImageReceiverView: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(receiver.mode.title).font(.largeTitle.weight(.semibold))
                Text(receiver.mode.summary).foregroundStyle(.secondary)
                AudioRoutingView(receiver: receiver)
                imageControls
                if receiver.mode == .sstv {
                    HStack {
                        Button("Preparar micrófono del Mac") { receiver.prepareSSTVMicrophone() }.disabled(receiver.busy)
                        Text("En el celular: Robot 36 para la primera prueba; envía también la cabecera VIS.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                SpectrumView(frame: receiver.frame, waterfall: receiver.waterfall, frequency: receiver.settings.frequency, shift: receiver.mode == .wefax ? 800 : 0) { frequency in
                    if !receiver.busy { receiver.settings.frequency = frequency }
                }
                HStack {
                    Text(receiver.source).font(.caption)
                    Spacer()
                    if let frame = receiver.frame {
                        Text("\(frame.levelDB, specifier: "%.1f") dBFS").monospacedDigit()
                        if frame.clipped { Label("Saturación: baja el volumen", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                    Button("Volver a decodificar") { if let url = receiver.lastURL { receiver.decode(url) } }.disabled(receiver.busy || receiver.lastURL == nil)
                    Button("Guardar PNG…") { receiver.exportImage() }.disabled(receiver.receivedImage == nil)
                }
                if receiver.busy && !receiver.live { ProgressView(value: receiver.progress) }
                Text(receiver.detail).font(.caption).foregroundStyle(.secondary)
                if receiver.live {
                    Text("\(receiver.samplesReceived) muestras recibidas · \(receiver.dropped) perdidas")
                        .font(.caption).monospacedDigit().foregroundStyle(receiver.dropped > 0 ? .orange : .secondary)
                }
                if let error = receiver.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if let image = receiver.receivedImage {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 420)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ContentUnavailableView("Esperando imagen", systemImage: "photo", description: Text(receiver.text.isEmpty ? "Abre audio o selecciona una entrada para recibir." : receiver.text))
                        .frame(height: 180)
                }
                Text(receiver.imageCaption.isEmpty ? receiver.text : receiver.imageCaption).font(.caption).foregroundStyle(.secondary)
                Text(receiver.mode == .hell ? "Hell por pulsos: imagen de doble traza, sin OCR ni cabecera. Elige la variante del transmisor y ajusta centro/reloj si la escritura se inclina. FSK Hell y Hell 80 pendientes." : "Recepción experimental. Para fax, inicio manual: indica el segundo de comienzo de imagen en un archivo. APT muestra A/B sin calibración radiométrica ni georreferenciación.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .sheet(isPresented: $receiver.showSSTVCatalog) { SSTVCatalogView(receiver: receiver) }
    }
    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if receiver.mode == .sstv {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading) {
                        Text("Formato SSTV").font(.caption)
                        Picker("Formato SSTV", selection: $receiver.settings.sstvFormat) {
                            ForEach(SSTVFormat.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 220)
                    }
                    Toggle("Auto VIS", isOn: $receiver.settings.imageAutoSync).toggleStyle(.checkbox)
                    Button("Catálogo completo…") { receiver.showSSTVCatalog = true }
                    Spacer(minLength: 0)
                }
                Toggle("Robot 36C: admitir paridad VIS no estándar", isOn: $receiver.settings.sstvRobot36Compatibility)
                    .toggleStyle(.checkbox).disabled(!receiver.settings.imageAutoSync && receiver.settings.sstvFormat != .robot36)
                Text("Con Auto VIS activo permite la cabecera Robot 36C (VIS 8) aunque su paridad sea no estándar. En modo manual selecciona Robot 36.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("Sincronización y reloj automáticos", isOn: $receiver.settings.sstvAutoCalibrate).toggleStyle(.checkbox)
                    Picker("Reducir ruido", selection: $receiver.settings.sstvNoiseReduction) {
                        ForEach(SSTVNoiseReduction.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 270)
                }
                Text("El reloj se estima con las sincronías de línea. Sin señal suficiente se conserva el reloj manual. Intensa suaviza más y puede perder detalles finos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if receiver.mode == .hell {
                HStack {
                    Picker("Variante Hell", selection: $receiver.settings.hellVariant) {
                        ForEach(HellVariant.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 255)
                    Text("\(receiver.settings.hellVariant.pixelRate, specifier: "%.3f") píxeles/s · ≈\(receiver.settings.hellVariant.bandwidthHz, specifier: "%.0f") Hz ocupados")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Invertir imagen", isOn: $receiver.settings.inverted)
                }.onChange(of: receiver.settings.hellVariant) { _, _ in receiver.applyHellVariant() }
                HStack {
                    Text("Umbral \(receiver.settings.threshold * 100, specifier: "%.1f") %").font(.caption)
                    Slider(value: $receiver.settings.threshold, in: 0.001...0.2).frame(width: 170)
                    Text("Lectura visual, sin OCR. El raster se pliega cada 160 columnas y conserva las últimas 1280.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 14) {
                if receiver.mode != .satelliteAPT {
                    VStack(alignment: .leading) {
                        Text("Centro de audio (Hz)").font(.caption)
                        TextField("Centro", value: $receiver.settings.frequency, format: .number).textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    Button(receiver.mode == .hell ? "1500 Hz" : "1900 Hz") { receiver.settings.frequency = receiver.mode == .hell ? max(1500, receiver.settings.hellVariant.bandwidthHz / 2 + 300) : 1900 }
                }
                if receiver.mode == .wefax {
                    Picker("LPM", selection: $receiver.settings.faxLinesPerMinute) {
                        ForEach([60.0,90,120,240], id: \.self) { Text(String(Int($0))).tag($0) }
                    }.frame(width: 100)
                    Picker("IOC", selection: $receiver.settings.faxIOC) {
                        Text("576").tag(576); Text("288").tag(288)
                    }.frame(width: 100)
                    Toggle("Invertir", isOn: $receiver.settings.inverted).toggleStyle(.checkbox)
                }
                if receiver.mode != .satelliteAPT {
                    VStack(alignment: .leading) {
                        Text("Inicio (s)").font(.caption)
                        TextField("Inicio", value: $receiver.settings.imageStartSeconds, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Reloj (ppm)").font(.caption)
                    TextField("ppm", value: $receiver.settings.imageClockPPM, format: .number).textFieldStyle(.roundedBorder).frame(width: 90)
                }
                if receiver.mode == .sstv {
                    VStack(alignment: .leading) {
                        Text("Color Y/Cr/Cb").font(.caption)
                        Picker("Color Y/Cr/Cb", selection: $receiver.settings.sstvColorRange) {
                            ForEach(SSTVColorRange.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 190)
                    }
                }
                Spacer(minLength: 0)
            }
            if receiver.mode == .sstv {
                HStack {
                    Text("Umbral \(receiver.settings.threshold * 100, specifier: "%.1f") %").font(.caption)
                    Slider(value: $receiver.settings.threshold, in: 0.001...0.1).frame(width: 170)
                    Text("0,1 % para una señal débil del micrófono. BT.601 para Robot/PD; usa Completo si el emisor emplea esa escala.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.disabled(receiver.busy)
    }
}
