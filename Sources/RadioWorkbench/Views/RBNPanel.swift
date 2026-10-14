import SwiftUI
import RadioCore

struct RBNPanel: View {
    @Bindable var store: RBNStore

    var body: some View {
        GroupBox("Actividad observada · Reverse Beacon Network") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    TextField("Indicativo o alias", text: $store.login).textFieldStyle(.roundedBorder).frame(width: 180)
                    Picker("Flujo", selection: $store.feed) {
                        ForEach(RBNFeed.allCases) { feed in Text(feed.rawValue).tag(feed) }
                    }.frame(width: 145).disabled(store.connected)
                    if store.connected {
                        Button("Desconectar", systemImage: "stop.circle") { store.disconnect() }
                    } else {
                        Button("Conectar", systemImage: "dot.radiowaves.left.and.right") { store.connect() }
                    }
                    Picker("Banda", selection: $store.bandFilter) {
                        ForEach(["Todas", "160 m", "80 m", "60 m", "40 m", "30 m", "20 m", "17 m", "15 m", "12 m", "10 m", "6 m", "2 m"], id: \.self) { Text($0) }
                    }.frame(width: 100)
                    Picker("Modo", selection: $store.modeFilter) {
                        ForEach(["Todos", "CW", "RTTY", "FT8"], id: \.self) { Text($0) }
                    }.frame(width: 95)
                    Spacer()
                    Button("Limpiar") { store.clear() }.disabled(store.spots.isEmpty)
                }
                HStack {
                    Text(store.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Text("\(store.visibleSpots.count) spots visibles · máximo 1.000 en memoria").font(.caption).foregroundStyle(.secondary)
                }
                if store.visibleSpots.isEmpty {
                    ContentUnavailableView("Sin spots", systemImage: "dot.radiowaves.left.and.right", description: Text(store.connected ? "RBN aún no ha enviado spots para estos filtros." : "Conecta para recibir actividad CW/RTTY o FT8. La app filtra bandas y modos en este Mac."))
                        .frame(minHeight: 110, maxHeight: 145)
                } else {
                    Table(Array(store.visibleSpots.prefix(60))) {
                        TableColumn("Hora") { spot in
                            Text(spot.receivedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!)))
                                .monospacedDigit()
                        }.width(70)
                        TableColumn("kHz") { spot in Text(spot.frequencyKHz.formatted(.number.precision(.fractionLength(1...1)))).monospacedDigit() }.width(85)
                        TableColumn("Banda") { spot in Text(spot.band ?? "—") }.width(65)
                        TableColumn("Señal") { spot in Text(spot.callsign).fontWeight(.semibold) }.width(95)
                        TableColumn("Modo") { spot in Text(spot.mode) }.width(60)
                        TableColumn("SNR") { spot in Text(spot.snrDB.map { "\($0) dB" } ?? "—").monospacedDigit() }.width(65)
                        TableColumn("WPM") { spot in Text(spot.speedWPM.map(String.init) ?? "—").monospacedDigit() }.width(55)
                        TableColumn("Skimmer") { spot in Text(spot.spotter) }.width(105)
                        TableColumn("Comentario") { spot in Text(spot.comment.isEmpty ? "—" : spot.comment) }.width(min: 85, ideal: 150)
                    }.frame(minHeight: 120, maxHeight: 280)
                }
                Text("RBN es una red de receptores voluntarios que detectan estaciones escuchadas, no una predicción de propagación. Los relés no filtran: RadioWorkbench conserva hasta 1.000 spots y aplica filtros localmente. Solo se envía el indicativo o alias para iniciar sesión; la app no transmite por radio.")
                    .font(.caption2).foregroundStyle(.secondary)
                Link("RBN · servidores y puertos", destination: URL(string: "https://beta.reversebeacon.net/pages/Telnet%2Bservers%2B30")!).font(.caption)
            }.padding(7)
        }
    }
}
