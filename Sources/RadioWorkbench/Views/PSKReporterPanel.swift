import SwiftUI
import RadioCore

struct PSKReporterPanel: View {
    @Bindable var store: PropagationStore
    let location: RadioLocation?
    let date: Date

    private var taskKey: String {
        "\(store.shareGridWithPSKReporter)-\(location?.latitude ?? .nan)-\(location?.longitude ?? .nan)"
    }

    var body: some View {
        GroupBox("Recepción observada · PSK Reporter") {
            VStack(alignment: .leading, spacing: 9) {
                Toggle(isOn: Binding(
                    get: { store.shareGridWithPSKReporter },
                    set: { store.setPSKGridSharing($0) }
                )) {
                    Text("Compartir una cuadrícula Maidenhead aproximada (4 caracteres, ~100 km) para consultar spots cercanos")
                }
                HStack {
                    Text(AppLocalization.text(store.pskStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    if store.pskBusy { ProgressView().controlSize(.small) }
                    Button("Consultar ahora") { Task { await store.refreshReceptionSpots(location: location) } }
                        .disabled(!store.shareGridWithPSKReporter || location == nil || store.pskBusy)
                }
                if store.shareGridWithPSKReporter, let snapshot = store.pskSnapshot {
                    if snapshot.spots.isEmpty {
                        Text("No hay spots en esta cuadrícula durante la última hora. Eso no demuestra que la banda esté cerrada.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Table(Array(snapshot.spots.prefix(20))) {
                            TableColumn("UTC") { spot in
                                Text(spot.reportedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!)))
                                    .monospacedDigit()
                            }.width(75)
                            TableColumn("Emisor", value: \.senderCallsign).width(100)
                            TableColumn("kHz") { spot in Text(spot.frequencyKHz.formatted(.number.precision(.fractionLength(0...1)))).monospacedDigit() }.width(90)
                            TableColumn("Modo") { spot in Text(spot.mode ?? "No informado") }.width(100)
                            TableColumn("Receptor", value: \.receiverCallsign).width(100)
                            TableColumn("Cuadrícula RX", value: \.receiverLocator).width(110)
                        }.frame(minHeight: 100, maxHeight: 220)
                    }
                    Text("Los datos son reportes comunitarios de decodificación digital en tu cuadrícula, con retraso y cobertura desigual. No representan toda la actividad de radio ni estiman automáticamente un contacto posible.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Link("PSK Reporter · API y límites", destination: URL(string: "https://pskreporter.info/pskdev.html")!)
                    Link("Mapa de actividad", destination: URL(string: "https://pskreporter.info/pskmap.html")!)
                    Spacer()
                }.font(.caption)
            }.padding(7)
        }
        .task(id: taskKey) {
            guard store.shareGridWithPSKReporter else { return }
            await store.refreshReceptionSpots(location: location)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await store.refreshReceptionSpots(location: location)
            }
        }
    }
}
