import SwiftUI
import AppKit
import RadioCore

struct PreferencesView: View {
    @Bindable var preferences: AppPreferencesStore
    @Bindable var updates: UpdateStore
    @Bindable var receiver: ReceiverStore
    @Bindable var broadcasts: BroadcastStore
    @Bindable var propagation: PropagationStore
    @Bindable var satellites: SatelliteConsultationStore
    @ViewState private var section = "general"
    private var locked: Bool { preferences.busy || receiver.busy || receiver.receptionLibrary.busy || receiver.receptionLibrary.sigMF.busy }
    var body: some View {
        HSplitView {
            List(selection: $section) {
                Label("General e idioma", systemImage: "globe").tag("general")
                Label("Audio", systemImage: "waveform").tag("audio")
                Label("Apariencia y rendimiento", systemImage: "paintpalette").tag("appearance")
                Label("Biblioteca", systemImage: "books.vertical").tag("library")
                Label("Datos y avisos", systemImage: "arrow.triangle.2.circlepath").tag("data")
                Label("Conexiones y diagnóstico", systemImage: "network").tag("connections")
            }.listStyle(.sidebar).frame(minWidth: 190, idealWidth: 220, maxWidth: 250)
            ScrollView {
                Form {
                    switch section {
                    case "audio": audio
                    case "appearance": appearance
                    case "library": library
                    case "data": data
                    case "connections": connections
                    default: general
                    }
                    if !preferences.status.isEmpty { Text(AppLocalization.text(preferences.status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.formStyle(.grouped).padding(16)
            }.frame(minWidth: 490)
        }.frame(minWidth: 760, idealWidth: 850, minHeight: 560, idealHeight: 650)
    }
    private var general: some View {
        Group {
            Section("General e idioma") {
                Picker("Idioma", selection: $preferences.values.language) {
                    Text(verbatim: "Español").tag("es"); Text(verbatim: "English").tag("en")
                }
                Text("El idioma cambia los controles y la ayuda. Los mensajes recibidos, nombres de archivos y datos de emisoras se conservan en su idioma original.").font(.caption)
                Toggle("Recordar la última sección", isOn: $preferences.values.rememberSection)
                Toggle("Restaurar ajustes de la sesión", isOn: $preferences.values.restoreSession)
                Text("Se recuperan modo, parámetros, entrada y canal. La captura, reproducción y las conexiones requieren una acción explícita.").font(.caption)
            }
            Section("Actualizaciones de la aplicación") {
                LabeledContent("Instalada", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Desarrollo")
                Toggle("Buscar actualizaciones automáticamente", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomatic($0) })).disabled(updates.configuration == nil)
                Button("Buscar actualizaciones…") { updates.check() }.disabled(updates.configuration == nil || updates.checking || receiver.busy)
                Text(AppLocalization.text(updates.status)).font(.caption).foregroundStyle(.secondary)
                Link("Publicaciones en GitHub", destination: URL(string: "https://github.com/AD0441/RadioWorkbench/releases")!)
            }
        }
    }
    private var audio: some View {
        Group {
            Section("Entrada predeterminada") {
                Picker("Fuente", selection: $preferences.values.defaultInputSource) {
                    Text("Dispositivo de audio").tag("device"); Text("Audio TCP local").tag("tcp")
                }
                Picker("Dispositivo", selection: $preferences.values.defaultDeviceUID) {
                    Text("Predeterminado de macOS").tag("")
                    if !preferences.values.defaultDeviceUID.isEmpty, !receiver.devices.contains(where: { $0.uid == preferences.values.defaultDeviceUID }) { Text("Dispositivo guardado desconectado").tag(preferences.values.defaultDeviceUID) }
                    ForEach(receiver.devices) { Text(verbatim: $0.name).tag($0.uid) }
                }
                Picker("Canal predeterminado", selection: $preferences.values.defaultChannel) {
                    Text("Mezclar canales").tag(-1)
                    ForEach(0..<32, id: \.self) { Text("Canal \($0 + 1)").tag($0) }
                }
                Button("Actualizar dispositivos") { receiver.refreshDevices() }
                Button("Aplicar predeterminados a recepción") { receiver.applyAudioDefaults(preferences.values) }.disabled(locked)
                Text("La sesión restaurada tiene prioridad. Aplica los predeterminados para reemplazar su entrada; si falta el canal se usa mezcla.").font(.caption)
            }.disabled(preferences.busy)
            Section("Perfiles de recepción") { InputProfilesView(receiver: receiver) }
            Section("Avisos de audio") {
                Toggle("Avisar de saturación", isOn: $preferences.values.warnClipping)
                Toggle("Avisar de muestras perdidas", isOn: $preferences.values.warnDroppedSamples)
                Text("Los contadores de diagnóstico continúan disponibles aunque ocultes los avisos.").font(.caption)
            }
        }
    }
    private var appearance: some View {
        Group {
            Section("Apariencia") {
                Picker("Tema", selection: $preferences.values.appearance) { Text("Sistema").tag("system"); Text("Claro").tag("light"); Text("Oscuro").tag("dark") }
                Stepper("Tamaño de texto: \(preferences.values.textSize) pt", value: $preferences.values.textSize, in: 11...20)
                Text("Ajusta el texto base y la escala de lectura. Las etiquetas técnicas conservan su jerarquía visual.").font(.caption)
            }
            Section("Waterfall y consumo") {
                Picker("Colores", selection: $preferences.values.waterfallPalette) { Text("Océano").tag("ocean"); Text("Ámbar").tag("amber"); Text("Escala de grises").tag("grayscale") }
                Picker("Velocidad máxima", selection: $preferences.values.waterfallFPS) { ForEach([5,10,15,25], id: \.self) { Text("\($0) cuadros/s").tag($0) } }
                Toggle("Perfil de menor consumo", isOn: $preferences.values.lowPower)
                Text("Menor consumo limita FFT y refresco a 5 cuadros/s y reduce el historial visual. El audio y el decodificador conservan su tasa. Detén la recepción antes de cambiar estos controles.").font(.caption)
            }.disabled(receiver.busy)
        }
    }
    private var library: some View {
        Group {
            Section("Grabaciones y biblioteca I/Q") {
                Text(verbatim: preferences.libraryRoot.path).font(.caption).textSelection(.enabled)
                Picker("Nombre sugerido al guardar audio", selection: $preferences.values.fileNaming) { Text("Nombre original").tag("original"); Text("Fecha UTC y modo").tag("utc-mode"); Text("Modo y fecha UTC").tag("mode-utc") }
                Text("Cada recepción conserva un identificador único para evitar colisiones. Esta regla propone el título al importar audio.").font(.caption)
                Button("Cambiar carpeta de biblioteca…") { preferences.chooseLibrary(receiver: receiver) }.disabled(locked)
                Text("Copia audio e I/Q y verifica los archivos antes de cambiar la ruta. La biblioteca anterior permanece disponible para recuperación.").font(.caption)
                Button("Mostrar carpeta") { NSWorkspace.shared.activateFileViewerSelecting([preferences.libraryRoot]) }
            }
            Section("Copias de seguridad y espacio") {
                LabeledContent("Espacio de las bibliotecas", value: ByteCountFormatter.string(fromByteCount: preferences.storageBytes, countStyle: .file))
                Button("Calcular espacio") { preferences.refreshStorage() }.disabled(preferences.busy)
                Button("Crear copia de seguridad ZIP…") { preferences.backupLibrary(receiver: receiver) }.disabled(locked)
                Text("Incluye audio, I/Q, índices, perfiles y preferencias. Para recuperar, extrae el ZIP en una carpeta local; conserva la copia y sus índices juntos. Los motores descargados se gestionan por separado.").font(.caption)
                Text("La papelera interna conserva archivos para restaurarlos. Usa la carpeta y la copia de seguridad para administrar el espacio; no hay borrado automático de recepciones.").font(.caption)
                if preferences.busy { ProgressView("Copiando y verificando archivos…") }
            }
        }.onAppear { preferences.refreshStorage() }
    }
    private var data: some View {
        Group {
            Section("Actualización de datos") {
                Toggle("Actualizar guías automáticamente", isOn: $preferences.values.guideAutomatic)
                Picker("Intervalo de guías", selection: $preferences.values.guideHours) { ForEach([1,6,12,24], id: \.self) { Text("\($0) horas").tag($0) } }.disabled(!preferences.values.guideAutomatic)
                Toggle("Actualizar satélites automáticamente", isOn: $preferences.values.satelliteAutomatic)
                Picker("Intervalo de satélites", selection: $preferences.values.satelliteHours) { ForEach([6,12,24,48], id: \.self) { Text("\($0) horas").tag($0) } }.disabled(!preferences.values.satelliteAutomatic)
                Toggle("Actualizar condiciones automáticamente", isOn: $preferences.values.conditionsAutomatic)
                Picker("Intervalo de condiciones", selection: $preferences.values.conditionsMinutes) { ForEach([3,5,15,30], id: \.self) { Text("\($0) minutos").tag($0) } }.disabled(!preferences.values.conditionsAutomatic)
                Text("Los botones Actualizar siguen disponibles en modo manual. Cada proveedor conserva su cadencia mínima y la fecha de sus datos.").font(.caption)
                Button("Actualizar guías ahora") { Task { await broadcasts.refresh() } }.disabled(broadcasts.busy)
                Button("Actualizar satélites ahora") { Task { await satellites.refresh() } }.disabled(satellites.busy)
                Button("Actualizar condiciones ahora") { Task { await propagation.refresh() } }.disabled(propagation.weatherBusy)
            }
            Section("Notificaciones de emisoras") {
                Toggle("Permitir avisos de favoritas", isOn: $preferences.values.notifications)
                Picker("Anticipación", selection: Binding(get: { broadcasts.alertLeadMinutes }, set: { broadcasts.setAlertLeadMinutes($0) })) { ForEach([0,5,10,15], id: \.self) { Text("\($0) minutos").tag($0) } }
                Text("La primera activación de un aviso de emisora solicita permiso a macOS. Desactivar esta opción retira los avisos programados y conserva las favoritas.").font(.caption)
            }
        }
    }
    private var connections: some View {
        Group {
            Section("Perfiles TCP y Rigctl") {
                TCPAudioControls(receiver: receiver)
                TextField("Puerto Rigctl local", value: Binding(get: { receiver.rigctl.port }, set: { receiver.rigctl.port = $0 }), format: .number.grouping(.never)).disabled(receiver.rigctl.busy)
                TextField("Nombre del perfil de conexión", text: $preferences.connectionName)
                Button("Guardar conexión actual") { preferences.saveConnection(receiver: receiver) }.disabled(receiver.busy || preferences.connections.count >= 64)
                Picker("Perfil guardado", selection: $preferences.selectedConnection) {
                    Text("Selecciona un perfil").tag(UUID?.none)
                    ForEach(preferences.connections) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                }
                HStack {
                    Button("Aplicar perfil") { preferences.applyConnection(receiver: receiver) }.disabled(preferences.selectedConnection == nil || receiver.busy || receiver.rigctl.busy)
                    Button("Eliminar perfil") { preferences.removeConnection() }.disabled(preferences.selectedConnection == nil)
                }
                Text("Solo se guardan parámetros locales. Aplicar no conecta, no sintoniza ni activa Rigctl.").font(.caption)
            }
            Section("Motores instalados") {
                ForEach(preferences.engineInventory.keys.sorted(), id: \.self) { name in LabeledContent(name, value: AppLocalization.text(preferences.engineInventory[name] == true ? "Disponible" : "No instalado")) }
            }
            Section("Diagnóstico") {
                Button("Exportar diagnóstico local…") { preferences.exportDiagnostic(receiver: receiver) }
                Text("Incluye versión, motores y contadores. No contiene audio, texto recibido, indicativos, ubicaciones ni rutas de archivos. Se exporta solo al solicitarlo.").font(.caption)
            }
        }
    }
}
