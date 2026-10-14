import SwiftUI
import RadioCore

private struct SSTVRecord: Decodable {
    let name: String
    let family: String
    let identification: String?
    let vis_code: Int?
    let width: Int?
    let height: Int?
    let evidence_status: String
    let source_urls: [String]
}
private struct SSTVCatalogDocument: Decodable { let modes: [SSTVRecord] }
private struct SSTVCatalogEntry: Identifiable {
    let id: Int
    let record: SSTVRecord
    var native: Bool {
        func normalized(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
        return SSTVFormat.allCases.contains { normalized($0.rawValue) == normalized(record.name) }
    }
}

struct SSTVCatalogView: View {
    @Bindable var receiver: ReceiverStore
    private let entries: [SSTVCatalogEntry]
    init(receiver: ReceiverStore) {
        self.receiver = receiver
        if let url = Bundle.main.url(forResource: "sstv-modes", withExtension: "json"),
           let data = try? Data(contentsOf: url), let document = try? JSONDecoder().decode(SSTVCatalogDocument.self, from: data) {
            entries = document.modes.enumerated().map { SSTVCatalogEntry(id: $0.offset, record: $0.element) }
        } else { entries = [] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Catálogo SSTV").font(.title.bold())
                    Text("\(entries.count) perfiles y variantes investigados; \(SSTVFormat.allCases.count - 1) formatos en el motor experimental.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cerrar") { receiver.showSSTVCatalog = false }.keyboardShortcut(.cancelAction)
            }
            TextField("Buscar formato o familia…", text: $receiver.sstvCatalogSearch).textFieldStyle(.roundedBorder)
            Table(entries.filter { receiver.sstvCatalogSearch.isEmpty || $0.record.name.localizedCaseInsensitiveContains(receiver.sstvCatalogSearch) || $0.record.family.localizedCaseInsensitiveContains(receiver.sstvCatalogSearch) }) {
                TableColumn("Formato") { Text($0.record.name) }.width(min: 120, ideal: 190)
                TableColumn("Familia") { Text($0.record.family) }.width(min: 80, ideal: 100)
                TableColumn("VIS") { row in
                    if let code = row.record.vis_code {
                        Text(row.record.identification == "VIS-16-LSB" ? String(format: "0x%04X", code) : row.record.identification == "N-VIS-24" ? "N \(code)" : String(code))
                    } else { Text("Otro / n.d.") }
                }.width(80)
                TableColumn("Raster") { row in
                    Text(row.record.width.flatMap { w in row.record.height.map { "\(w) × \($0)" } } ?? "Sin verificar")
                }.width(110)
                TableColumn("Recepción aquí") { row in
                    Text(row.native ? "Experimental" : "Motor pendiente").foregroundStyle(row.native ? .primary : .secondary)
                }.width(130)
                TableColumn("Fuente") { row in
                    if let source = row.record.source_urls.first, let url = URL(string: source) { Link("Ver", destination: url) }
                }.width(50)
            }
            Text("VIS no identifica siempre un formato de forma única. MP/MR/ML usan VIS16; MP-N/MC-N usan N-VIS24. AVT y otros perfiles históricos siguen pendientes. Los formatos catalogados no equivalen a motores implementados.")
                .font(.caption).foregroundStyle(.secondary)
            Text("SSTV analógica y HAMDRM/EasyPal/SSDV son protocolos distintos.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 850, height: 590)
    }
}
