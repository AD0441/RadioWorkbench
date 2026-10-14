import SwiftUI
import RadioCore

struct AudioRoutingView: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InputProfilesView(receiver: receiver)
            HStack {
                Picker("Entrada de audio", selection: $receiver.selectedDeviceID) {
                    Text("Predeterminada del sistema").tag(UInt32(0))
                    ForEach(receiver.devices) { device in
                        Text("\(device.name) · \(Int(device.sampleRate)) Hz · \(device.channels) ch").tag(device.id)
                    }
                }.frame(maxWidth: 430).disabled(receiver.busy)
                    .onChange(of: receiver.selectedDeviceID) { receiver.inputSelectionChanged() }
                Button("Actualizar", systemImage: "arrow.clockwise") { receiver.refreshDevices() }.disabled(receiver.busy)
                Spacer()
            }
            Picker("Canal de audio", selection: $receiver.settings.audioChannel) {
                Text("Mezclar canales").tag(AudioChannelSelection.mix)
                ForEach(0..<receiver.availableChannelCount, id: \.self) { index in
                    Text(AudioChannelSelection.channel(index).label).tag(AudioChannelSelection.channel(index))
                }
            }
            // Recreate the native popup when a demo changes the selection;
            // AppKit can retain its previous checked item across a fast decode.
            .id(receiver.settings.audioChannel)
            .frame(width: 360).disabled(receiver.busy)
            HStack {
                Picker("SDR++", selection: $receiver.rfModulation) {
                    ForEach(RFModulation.allCases.filter { $0 != .iq }) { Text($0.rawValue).tag($0) }
                }.frame(width: 180)
                Text("Filtro RF")
                TextField("Hz", value: $receiver.rfBandwidth, format: .number).frame(width: 90).textFieldStyle(.roundedBorder)
                Text("Hz · SDR++ a 48 kHz").foregroundStyle(.secondary)
                Spacer()
            }.font(.caption)
            Text(receiver.mode.receptionProfile.audioBand + ". " + receiver.mode.receptionProfile.note)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if receiver.mode == .sstv && receiver.settings.sstvFormat.isNarrow {
                Text("Narrow: cabecera 1900/2100 Hz; vídeo 2044–2300 Hz. Conserva la cabecera completa; en USB, reducir solo el ancho del filtro puede eliminar estos tonos.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(receiver.selectedInput?.isBuiltIn == true
                 ? "Micrófono del Mac: pulsa Escuchar antes de emitir desde el celular. Debajo se muestra la tasa efectiva de captura. Los ajustes RF son una guía para SDR++."
                 : "En SDR++: Audio / New Audio → VB-Cable → 48000 Hz. Aquí selecciona VB-Cable y pulsa Escuchar. Estos ajustes RF se aplican en SDR++, no automáticamente.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
