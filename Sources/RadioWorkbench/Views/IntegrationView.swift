import SwiftUI
import RadioCore

struct IntegrationView: View {
    let mode: RadioMode
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: mode.symbol).font(.system(size: 40)).foregroundStyle(.tint)
                Text(mode.title).font(.largeTitle.weight(.semibold))
                Label("Motor pendiente de integración", systemImage: "puzzlepiece.extension").foregroundStyle(.secondary)
                Text(mode.summary).font(.title3).fixedSize(horizontal: false, vertical: true)
                GroupBox("Ruta de desarrollo") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Este modo forma parte del alcance de RadioWorkbench. Todavía no decodifica señales en esta versión.")
                        Text("Antes de habilitarlo: integrar el motor, comprobar entrada de audio o I/Q, validar grabaciones y revisar su licencia.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if let url = mode.sourceURL { Link("Ver candidato en GitHub", destination: url) }
                if [.rtty, .morse, .navtex, .gmdss, .packet, .satelliteAPT].contains(mode),
                   FileManager.default.fileExists(atPath: "/Applications/SDRangel.app") {
                    GroupBox("Complemento instalado") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SDRangel incluye un motor para esta familia de señales. Puedes abrirlo para trabajar con su recepción SDR.")
                            Button("Abrir SDRangel") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/SDRangel.app")) }
                            Text("Se abre como aplicación independiente; el audio y los resultados todavía no se intercambian con RadioWorkbench.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                GroupBox("Extensiones investigadas") {
                    VStack(alignment: .leading, spacing: 10) {
                        Link("fldigi · modos de audio y WEFAX", destination: URL(string: "https://www.w1hkj.org/")!)
                        Link("acarsdec · ACARS desde WAV", destination: URL(string: "https://github.com/f00b4r0/acarsdec")!)
                        Link("xng · aviación y marítimo desde I/Q", destination: URL(string: "https://github.com/airframesio/xng")!)
                        Link("Dire Wolf · packet y APRS", destination: URL(string: "https://github.com/wb2osz/direwolf")!)
                        Link("QSSTV · imágenes SSTV", destination: URL(string: "https://github.com/tomtastic/QSSTV")!)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text("Los enlaces abren documentación. Los motores externos se instalan e integran por separado.").font(.caption).foregroundStyle(.secondary)
            }.padding(36).frame(maxWidth: 760, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
