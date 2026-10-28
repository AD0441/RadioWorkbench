import SwiftUI
import RadioCore

struct InputProfilesView: View {
    @Bindable var receiver: ReceiverStore
    private var selection: Binding<UUID?> {
        Binding(get: { receiver.selectedProfileID }, set: { id in
            if let id { receiver.applyInputProfile(id) } else { receiver.selectedProfileID = nil }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Perfil de recepción", selection: selection) {
                    Text("Ajustes actuales").tag(UUID?.none)
                    ForEach(receiver.inputProfiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 430)
                Button("Guardar como…") {
                    receiver.newProfileName = "\(receiver.selectedInput?.name ?? "Entrada") · \(receiver.mode.title)"
                    receiver.showsProfileEditor = true
                }
                Menu("Perfil") {
                    Button("Actualizar con estos ajustes") { receiver.saveInputProfile(updating: true) }
                    Button("Eliminar perfil", role: .destructive) { receiver.removeInputProfile() }
                }.disabled(receiver.selectedProfileID == nil)
                Spacer(minLength: 0)
            }.disabled(receiver.busy)
            if !receiver.profileNotice.isEmpty { Text(AppLocalization.text(receiver.profileNotice)).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $receiver.showsProfileEditor) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Guardar perfil de recepción").font(.headline)
                Text("Entrada, canal, modo, sensibilidad, SSTV y guía de SDR++ se conservarán para próximas sesiones.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Nombre del perfil", text: $receiver.newProfileName).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancelar") { receiver.showsProfileEditor = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Guardar") { receiver.saveInputProfile(updating: false) }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 450)
        }
    }
}
