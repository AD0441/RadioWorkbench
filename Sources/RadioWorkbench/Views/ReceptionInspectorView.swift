import CoreGraphics
import SwiftUI
import RadioCore

/// Observes configuration only. The live visualisation remains in its own view
/// and cannot invalidate this inspector at the audio-frame cadence.
struct ReceptionInspectorView: View {
    let mode: RadioMode
    let settings: DecoderSettings
    var canApply = true
    var onApply: ((ReceptionProfile) -> Void)? = nil
    var onOpenWorkshop: ((SignalReference) -> Void)? = nil
    @ViewState private var selectedBand: ReceptionBandVariant = .standard
    @ViewState private var showReference = false

    private var band: ReceptionBandVariant {
        mode.receptionBandVariants.contains(selectedBand) ? selectedBand : mode.receptionBandVariants[0]
    }
    private var profile: ReceptionProfile { mode.receptionProfile(settings: settings, variant: band) }
    private var reference: SignalReference? { SignalReference.matching(mode: mode, settings: settings) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Preparar el SDR", systemImage: "slider.horizontal.3").font(.headline)
                Text(AppLocalization.text(mode.title)).font(.title3.weight(.semibold))
                if !mode.isAudioAvailable {
                    Label("Identificar · sin motor integrado", systemImage: "info.circle").foregroundStyle(.orange)
                }
                if mode.receptionBandVariants.count > 1 {
                    Picker("Entorno", selection: Binding(get: { band }, set: { selectedBand = $0 })) {
                        ForEach(mode.receptionBandVariants) { Text(AppLocalization.text($0.rawValue)).tag($0) }
                    }.pickerStyle(.menu)
                }
                field("Demodulación en SDR++", profile.modulation.rawValue)
                field("Modulación de la señal", mode.signalModulation(settings: settings))
                field("Filtro RF inicial", "\((profile.rfBandwidth / 1000).formatted(.number.precision(.fractionLength(0...2)))) kHz")
                field("Audio que debe llegar", profile.audioBand)
                Text(AppLocalization.text(profile.note)).foregroundStyle(.secondary)
                Text(AppLocalization.text(mode.audioInputRecommendation)).foregroundStyle(.secondary)
                if settings.audioChannel == .mix {
                    Text("Canal: mezcla. Si el origen es estéreo, comprueba que ambos canales contienen la misma señal y fase.").foregroundStyle(.secondary)
                } else { field("Canal elegido", settings.audioChannel.label) }
                if let onApply {
                    Button("Aplicar perfil en la app") { onApply(profile) }.buttonStyle(.borderedProminent).disabled(!canApply)
                    Text("Prepara los ajustes de RAZIEL. Sintoniza frecuencia, modo y ancho en SDR++ manualmente o usa la acción optativa de Rigctl.")
                        .foregroundStyle(.secondary)
                }
                Divider()
                if let reference {
                    Text("Referencia nominal de audio").font(.headline)
                    Text(AppLocalization.text(reference.title))
                    Button(showReference ? "Ocultar referencia visual" : "Ver espectro y waterfall") { showReference.toggle() }
                    if showReference { InspectorReferencePreview(reference: reference) }
                    if let onOpenWorkshop { Button("Abrir esta muestra en el taller") { onOpenWorkshop(reference) } }
                    Text("Muestra de laboratorio. Sus ejes representan audio demodulado, no el espectro RF/IQ del SDR. Los ajustes de tu señal pueden diferir de los del WAV.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sin WAV de referencia verificado para esta variante. La ficha y el catálogo externo sirven para explorar; no acreditan una decodificación.")
                        .foregroundStyle(.secondary)
                }
                Divider()
                if mode == .digitalVoice {
                    Link(settings.digitalVoiceProtocol.receptionPreset.sourceTitle, destination: settings.digitalVoiceProtocol.receptionPreset.sourceURL)
                } else if let url = mode.sourceURL { Link("Documentación y fuente del motor", destination: url) }
                Link("Artemis · catálogo externo", destination: URL(string: "https://aresvalley.github.io/Artemis/")!)
                Text("El ancho ocupado de una señal y el filtro RF práctico del receptor son magnitudes distintas. No se importaron los medios externos de Artemis.")
                    .foregroundStyle(.secondary)
            }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .frame(minWidth: 250, idealWidth: 285, maxWidth: 320)
        .background(.background)
        .onChange(of: mode) { selectedBand = mode.receptionBandVariants[0]; showReference = false }
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLocalization.text(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(AppLocalization.text(value)).font(.callout)
        }
    }
}

private struct InspectorReferencePreview: View {
    let reference: SignalReference
    @ViewState private var result: SignalProbeResult?
    @ViewState private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let result {
                SignalSpectrumPlot(result: result, height: 90)
                SignalWaterfallPlot(result: result, height: 110)
                Text("\(result.sampleRate.formatted()) Hz · primeros \(result.secondsAnalyzed.formatted(.number.precision(.fractionLength(1)))) s")
            } else if let error { Text(AppLocalization.text(error)).foregroundStyle(.secondary) }
            else { ProgressView("Calculando desde el WAV…") }
        }
        .task(id: reference.id) {
            result = nil; error = nil
            guard let url = Bundle.main.url(forResource: reference.fileName, withExtension: "wav", subdirectory: "Examples") else {
                error = "La muestra no está disponible en este paquete."; return
            }
            let limit = reference.analysisFrequencyLimit
            let work = Task.detached(priority: .utility) { try SignalProbe.analyze(url: url, frequencyLimit: limit) }
            do {
                let probe = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled else { return }
                result = probe
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

struct SignalSpectrumPlot: View {
    let result: SignalProbeResult
    var height: CGFloat = 140
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Espectro medio de audio · −100…0 dBFS").foregroundStyle(.secondary)
            Canvas { context, size in
                var path = Path()
                for index in result.bins.indices {
                    let point = CGPoint(x: Double(index) / Double(result.bins.count) * size.width,
                                        y: (1 - min(1, max(0, (Double(result.bins[index]) + 100) / 100))) * size.height)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(.cyan), lineWidth: 1.25)
            }.frame(height: height).padding(6).background(.black, in: RoundedRectangle(cornerRadius: 6))
            HStack { Text("0 Hz"); Spacer(); Text("\(Int(result.upperFrequency)) Hz") }.foregroundStyle(.secondary)
        }.font(.caption2).accessibilityElement(children: .combine)
    }
}

struct SignalWaterfallPlot: View {
    let result: SignalProbeResult
    var height: CGFloat = 180

    private var image: CGImage? {
        guard let columns = result.waterfall.first?.count, columns > 0, !result.waterfall.isEmpty,
              result.waterfall.allSatisfy({ $0.count == columns }) else { return nil }
        var pixels = [UInt8](); pixels.reserveCapacity(columns * result.waterfall.count * 4)
        for row in result.waterfall {
            for value in row {
                let unit = value.isFinite ? min(1, max(0, (Double(value) + 100) / 100)) : 0
                let red = min(1, max(0, (unit - 0.5) * 2))
                let green = min(1, max(0, unit * 2 - 0.2))
                let blue = min(1, max(0, unit < 0.65 ? unit * 2 : (1 - unit) * 2.8))
                pixels.append(contentsOf: [UInt8(red * 255), UInt8(green * 255), UInt8(blue * 255), 255])
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: columns, height: result.waterfall.count, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: columns * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Waterfall de audio · tiempo hacia abajo").foregroundStyle(.secondary)
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.none).frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack { Text("0 Hz"); Spacer(); Text("\(Int(result.upperFrequency)) Hz") }.foregroundStyle(.secondary)
            Text("0 → \(result.secondsAnalyzed.formatted(.number.precision(.fractionLength(1)))) s · color fijo −100…0 dBFS")
                .foregroundStyle(.secondary)
        }.font(.caption2).accessibilityElement(children: .combine)
    }
}
