import SwiftUI
import RadioCore

struct ReceiverSpectrumView: View {
    let receiver: ReceiverStore
    var body: some View {
        SpectrumView(frame: receiver.visualization.frame, waterfall: receiver.visualization.waterfall,
                     frequency: receiver.settings.frequency, shift: shift,
                     showsTuningMarker: receiver.mode != .digitalVoice && !receiver.mode.isMultimon) { frequency in
            if !receiver.busy && !receiver.mode.isMultimon && ![.digitalVoice, .selectiveTones, .acars, .ale].contains(receiver.mode) {
                receiver.settings.frequency = frequency
            }
        }
    }
    private var shift: Double {
        switch receiver.mode {
        case .navtex, .sitorA: 170
        case .rtty: receiver.settings.shift
        case .wefax: 800
        default: 0
        }
    }
}

struct ReceiverLevelView: View {
    let visualization: ReceiverVisualization
    var imageMode = false
    var body: some View {
        if let frame = visualization.frame {
            Text("\(frame.levelDB, specifier: "%.1f") dBFS").monospacedDigit()
            if frame.clipped && visualization.warnClipping {
                Label(imageMode ? "Saturación: baja el volumen" : "Saturación", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct SpectrumView: View {
    let frame: SpectrumFrame?
    let waterfall: CGImage?
    let frequency: Double
    let shift: Double
    var showsTuningMarker = true
    var tune: (Double) -> Void
    var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                let upper = frame?.upperFrequency ?? 4000
                for i in 1...4 {
                    let y = size.height * Double(i) / 5
                    var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(.white.opacity(0.1)), lineWidth: 1)
                }
                if let bins = frame?.bins {
                    var path = Path()
                    for i in bins.indices {
                        let point = CGPoint(x: Double(i) / Double(bins.count) * size.width,
                                            y: size.height * (1 - min(1, max(0, (Double(bins[i]) + 100) / 100))))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(.cyan), lineWidth: 1.5)
                }
                for target in showsTuningMarker ? (shift > 0 ? [frequency - shift / 2, frequency + shift / 2] : [frequency]) : [] {
                    let x = target / upper * size.width
                    var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(.orange), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }.frame(height: 100)
                .overlay(alignment: .topLeading) { Text("ESPECTRO · AUDIO").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6)).padding(10) }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            if let waterfall {
                Image(decorative: waterfall, scale: 1).resizable().interpolation(.none).frame(height: 100)
            } else {
                Rectangle().fill(.clear).frame(height: 100).overlay(Text("Abre audio para explorar la señal").font(.caption).foregroundStyle(.white.opacity(0.5)))
            }
            HStack {
                Text("0 Hz"); Spacer(); Text("\(Int((frame?.upperFrequency ?? 4000) / 2)) Hz"); Spacer(); Text("\(Int(frame?.upperFrequency ?? 4000)) Hz")
            }.font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 10).padding(.vertical, 6)
        }.background(Color(red: 0.035, green: 0.055, blue: 0.08), in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onTapGesture { location in
                        tune(max(100, min(5900, location.x / geometry.size.width * (frame?.upperFrequency ?? 4000))))
                    }
                }
                .allowsHitTesting(showsTuningMarker)
            }
    }
}
