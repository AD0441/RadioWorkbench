import SwiftUI
import RadioCore

struct TCPAudioControls: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Dirección local", selection: $receiver.networkPCM.host) {
                    Text("127.0.0.1 · IPv4").tag("127.0.0.1")
                    Text("::1 · IPv6").tag("::1")
                }.frame(width: 230)
                Text("Puerto")
                TextField("Puerto", value: $receiver.networkPCM.port, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 85)
                Picker("Formato", selection: $receiver.networkPCM.format) {
                    ForEach(NetworkPCMSampleFormat.allCases) { Text($0.title).tag($0) }
                }.frame(width: 270)
            }
            HStack {
                Text("Tasa Hz")
                TextField("Hz", value: $receiver.networkPCM.sampleRate, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 100)
                Stepper("\(receiver.networkPCM.channels) canal(es)", value: $receiver.networkPCM.channels, in: 1...32)
                    .frame(width: 170).onChange(of: receiver.networkPCM.channels) { receiver.inputSelectionChanged() }
                Text("PCM crudo, canales intercalados, sin cabecera WAV").foregroundStyle(.secondary)
            }
            Text("Pulsa Escuchar para conectar. No se detecta el formato automáticamente ni se reconecta al cerrar. La tasa y los canales deben coincidir con Brown.").foregroundStyle(.secondary)
            if !receiver.networkNotice.isEmpty { Text(receiver.networkNotice).textSelection(.enabled) }
            if receiver.live {
                let state = receiver.tcpInput.snapshot
                Text("\(state.bytesReceived) bytes · \(state.framesDecoded) cuadros PCM · \(state.droppedSamples) muestras descartadas por el búfer local")
                    .monospacedDigit().textSelection(.enabled)
            }
        }.font(.caption).disabled(receiver.busy)
    }
}
