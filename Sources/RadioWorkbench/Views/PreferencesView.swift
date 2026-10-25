import SwiftUI
import RadioCore

struct PreferencesView: View {
    @Bindable var updates: UpdateStore
    @Bindable var receiver: ReceiverStore
    var body: some View {
        TabView {
            Form {
                LabeledContent("Motor", value: "Swift + Accelerate · arm64")
                Text("La entrada y el canal se seleccionan en cada recepción. El asistente comprueba la conexión sin cambiar los ajustes globales de macOS.")
                Text("Las grabaciones y la biblioteca se conservan al actualizar la aplicación.").foregroundStyle(.secondary)
            }.padding(24).tabItem { Label("General", systemImage: "gear") }
            Form {
                LabeledContent("Instalada", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Desarrollo") + " · build " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))
                Toggle("Buscar actualizaciones automáticamente", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomatic($0) }))
                    .disabled(updates.configuration == nil)
                Button("Buscar actualizaciones…") { updates.check() }.disabled(updates.configuration == nil || updates.checking || receiver.busy)
                if updates.checking { ProgressView().controlSize(.small) }
                Text(updates.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Link("Ver publicaciones de GitHub", destination: URL(string: "https://github.com/AD0441/RadioWorkbench/releases")!)
                Text("Sparkle verifica la firma Ed25519 de las actualizaciones. La clave privada se conserva fuera de la aplicación y del repositorio.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).tabItem { Label("Actualizaciones", systemImage: "arrow.triangle.2.circlepath") }
            Form {
                Text("Biblioteca → I/Q · SigMF").font(.headline)
                Text("Importa y exporta muestras con sus metadatos. Los pares compatibles permiten preparar SatDump sin volver a introducir frecuencia, tasa y fecha.")
                Text("Las grabaciones se copian localmente y se verifican con SHA-512. La papelera conserva las muestras hasta su restauración; esta versión no las elimina automáticamente.").font(.caption).foregroundStyle(.secondary)
                Link("Especificación SigMF", destination: URL(string: "https://sigmf.org/")!)
            }.padding(24).tabItem { Label("I/Q y biblioteca", systemImage: "waveform.path") }
        }.frame(width: 580, height: 330)
    }
}
