import SwiftUI
import AppKit

/// Display identity is separate from the persistent bundle/data identity.
@MainActor enum AppBrand {
    static let name = "RAZIEL"
    static let donationURL = URL(string: "https://ko-fi.com/C0C51WQ1T0")!
    static let repositoryURL = URL(string: "https://github.com/AD0441/RadioWorkbench")!
    static let icon: NSImage? = {
        let url = Bundle.main.url(forResource: "RazielIcon", withExtension: "png", subdirectory: "Brand")
            ?? Bundle.module.url(forResource: "RazielIcon", withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) }
    }()
}

/// Matches the sidebar footer structure used by METATRON.
struct SidebarBrandFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RazielSymbol().stroke(.tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 29, height: 29).accessibilityHidden(true)
                Text(verbatim: AppBrand.name).font(.title3.weight(.semibold)).foregroundStyle(.tint)
            }
            Label("Audio y datos en tu Mac", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
            SettingsLink {
                Label("Ajustes", systemImage: "gearshape").font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Abrir Ajustes: idioma, audio, apariencia y biblioteca.")
            Text("Creado por Sebastián Pastén F.").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }
}

/// Small geometric mark: no bitmap decoding is needed in the main sidebar.
private struct RazielSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.5,0.08)); path.addLine(to: p(0.5,0.82))
        path.move(to: p(0.43,0.92)); path.addLine(to: p(0.5,0.82)); path.addLine(to: p(0.57,0.92)); path.closeSubpath()
        path.addRect(CGRect(x: rect.minX + rect.width * 0.41, y: rect.minY + rect.height * 0.92, width: rect.width * 0.18, height: rect.height * 0.05))
        for radius in [0.24,0.39] {
            path.move(to: p(0.5 + radius * cos(78 * .pi / 180),0.47 - radius * sin(78 * .pi / 180)))
            path.addArc(center: p(0.5,0.47), radius: rect.width * radius, startAngle: .degrees(-78), endAngle: .degrees(72), clockwise: false)
            path.move(to: p(0.5 - radius * cos(78 * .pi / 180),0.47 - radius * sin(78 * .pi / 180)))
            path.addArc(center: p(0.5,0.47), radius: rect.width * radius, startAngle: .degrees(-102), endAngle: .degrees(-252), clockwise: true)
        }
        path.move(to: p(0.12,0.5)); path.addCurve(to: p(0.46,0.54), control1: p(0.26,0.7), control2: p(0.26,0.3))
        path.move(to: p(0.54,0.54)); path.addCurve(to: p(0.88,0.5), control1: p(0.74,0.3), control2: p(0.74,0.7))
        return path
    }
}

struct ProjectSupportView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let icon = AppBrand.icon { Image(nsImage: icon).resizable().frame(width: 60, height: 60).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: AppBrand.name).font(.title2.weight(.semibold))
                    Text("Escucha, decodifica y explora señales de radio.").foregroundStyle(.secondary)
                    Text("Creado por Sebastián Pastén F.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Tu apoyo ayuda a mantener el desarrollo y las pruebas. También puedes contribuir con ideas, traducciones e informes de errores.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link(destination: AppBrand.donationURL) {
                    Label("Apoyar en Ko-fi", systemImage: "cup.and.saucer.fill")
                }.buttonStyle(.bordered)
                    .help("Abre Ko-fi en tu navegador. La donación es voluntaria.")
                Link("Proyecto en GitHub", destination: AppBrand.repositoryURL)
            }
        }.padding(.vertical, 4)
    }
}
