import Foundation
import PDFKit
import RadioCore

struct SUBTELRepeaterSnapshot: Codable, Sendable {
    var repeaters: [VHFRepeater]
    var sourceURL: URL
    var sourceDate: String
    var fetchedAt: Date
}

struct SUBTELCallsignSnapshot: Codable, Sendable {
    var callsigns: [LicensedCallsign]
    var sourceDate: String
    var fetchedAt: Date
}

actor SUBTELDataService {
    static let directoryURL = URL(string: "https://www.subtel.gob.cl/inicio-concesionario/servicios-de-telecomunicaciones/servicios-de-radio-aficionados/")!
    private let transport: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let fileManager = FileManager.default
    private let supportDirectory: URL

    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, response)
    }) {
        self.transport = transport
        supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RadioWorkbench", isDirectory: true)
    }

    func cachedRepeaters() -> SUBTELRepeaterSnapshot? {
        guard let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("subtel-repeaters.json")), data.count <= 8_000_000 else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SUBTELRepeaterSnapshot.self, from: data)
    }

    func cachedCallsigns() -> SUBTELCallsignSnapshot? {
        guard let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("subtel-callsigns.json")), data.count <= 8_000_000 else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SUBTELCallsignSnapshot.self, from: data)
    }

    func refreshRepeaters(now: Date = Date()) async throws -> SUBTELRepeaterSnapshot {
        let html = try await fetchHTML()
        guard let (url, sourceDate) = Self.findDownload(in: html, phrase: "Listado de Repetidores", allowedExtension: "xlsx") else {
            throw ServiceError.sourceLinkNotFound("SUBTEL no publicó un enlace XLSX identificable para el listado de repetidoras.")
        }
        let data = try await fetchFile(url, maximumBytes: 24_000_000)
        let rows = try XLSXTableReader.read(data: data)
        let repeaters = SUBTELRepeaterParser.parse(rows: rows)
        guard !repeaters.isEmpty else { throw ServiceError.invalidSource("El Excel oficial se descargó, pero no se reconocieron sus columnas. Se conserva la copia anterior.") }
        let snapshot = SUBTELRepeaterSnapshot(repeaters: repeaters, sourceURL: url, sourceDate: sourceDate, fetchedAt: now)
        try save(snapshot, name: "subtel-repeaters.json")
        return snapshot
    }

    func refreshCallsigns(now: Date = Date()) async throws -> SUBTELCallsignSnapshot {
        let html = try await fetchHTML()
        let general = Self.findDownload(in: html, phrase: "Licencias de Radioaficionados", allowedExtension: "pdf")
        let aspirants = Self.findDownload(in: html, phrase: "Licencias de Aspirantes", allowedExtension: "pdf")
        guard let general, let aspirants else { throw ServiceError.sourceLinkNotFound("No se encontraron los dos listados públicos de licencias en SUBTEL.") }
        async let generalData = fetchFile(general.0, maximumBytes: 30_000_000)
        async let aspirantsData = fetchFile(aspirants.0, maximumBytes: 30_000_000)
        let (regular, candidate) = try await (generalData, aspirantsData)
        let records = SUBTELCallsignParser.parse(Self.pdfText(regular), category: "Novicio / General / Superior")
            + SUBTELCallsignParser.parse(Self.pdfText(candidate), category: "Aspirante")
        guard !records.isEmpty else { throw ServiceError.invalidSource("Los PDF se descargaron, pero no se pudieron extraer indicativos. Se conserva la copia anterior.") }
        let snapshot = SUBTELCallsignSnapshot(callsigns: records, sourceDate: general.1, fetchedAt: now)
        try save(snapshot, name: "subtel-callsigns.json")
        return snapshot
    }

    private func fetchHTML() async throws -> String {
        var request = URLRequest(url: Self.directoryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("RadioWorkbench/0.8.10 (SUBTEL amateur-radio lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == "www.subtel.gob.cl",
              data.count <= 3_000_000, let text = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return text
    }

    private func fetchFile(_ url: URL, maximumBytes: Int) async throws -> Data {
        guard url.scheme == "https", url.host == "www.subtel.gob.cl", url.path.hasPrefix("/wp-content/uploads/") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue("RadioWorkbench/0.8.10 (SUBTEL amateur-radio lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        guard response.statusCode == 200, response.url?.scheme == "https", response.url?.host == "www.subtel.gob.cl",
              data.count > 100, data.count <= maximumBytes else { throw URLError(.badServerResponse) }
        return data
    }

    private func save<T: Encodable>(_ value: T, name: String) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: supportDirectory.appendingPathComponent(name), options: .atomic)
    }

    private static func findDownload(in html: String, phrase: String, allowedExtension: String) -> (URL, String)? {
        let itemRegex = try? NSRegularExpression(pattern: #"(?is)<li\b[^>]*>.*?</li>"#)
        let range = NSRange(html.startIndex..., in: html)
        for match in itemRegex?.matches(in: html, range: range) ?? [] {
            guard let swiftRange = Range(match.range, in: html) else { continue }
            let item = String(html[swiftRange])
            let plain = item.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            guard plain.localizedCaseInsensitiveContains(phrase.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_CL"))) else { continue }
            let linkRegex = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#)
            for link in linkRegex?.matches(in: item, range: NSRange(item.startIndex..., in: item)) ?? [] {
                guard let valueRange = Range(link.range(at: 1), in: item),
                      let resolved = URL(string: String(item[valueRange]), relativeTo: directoryURL)?.absoluteURL,
                      resolved.pathExtension.lowercased() == allowedExtension else { continue }
                let date = plain.range(of: #"vigentes?\s+al\s+[^.)]+"#, options: .regularExpression).map { String(plain[$0]) } ?? "Fecha no indicada por la página"
                return (resolved, date)
            }
        }
        return nil
    }

    private static func pdfText(_ data: Data) -> String {
        guard data.count <= 30_000_000, let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    enum ServiceError: LocalizedError {
        case sourceLinkNotFound(String)
        case invalidSource(String)
        var errorDescription: String? { switch self { case .sourceLinkNotFound(let value), .invalidSource(let value): value } }
    }
}

private enum XLSXTableReader {
    static func read(data: Data) throws -> [[String]] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("radioworkbench-xlsx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("source.xlsx")
        try data.write(to: archive, options: .atomic)
        let sharedXML = try? extract(archive, entry: "xl/sharedStrings.xml")
        let sheetXML = try extract(archive, entry: "xl/worksheets/sheet1.xml")
        let shared = sharedXML.map(SharedStringsParser.parse) ?? []
        let rows = WorksheetParser.parse(sheetXML, sharedStrings: shared)
        guard !rows.isEmpty else { throw SUBTELDataService.ServiceError.invalidSource("La primera hoja del XLSX está vacía.") }
        return rows
    }

    private static func extract(_ archive: URL, entry: String) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-p", archive.path, entry]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); let result = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, result.count <= 16_000_000 else { throw SUBTELDataService.ServiceError.invalidSource("No se pudo leer \(entry) del Excel descargado.") }
        return result
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var values: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false
    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser(); let parser = XMLParser(data: data); parser.delegate = delegate
        _ = parser.parse(); return delegate.values
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "si" { inItem = true; current = "" }
        if elementName == "t", inItem { inText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { inText = false }
        if elementName == "si" { values.append(current); inItem = false }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var row: [Int: String] = [:]
    private var cellIndex: Int?
    private var cellType = ""
    private var value = ""
    private var inValue = false
    private var inInlineText = false
    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }
    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings); let parser = XMLParser(data: data); parser.delegate = delegate
        _ = parser.parse(); return delegate.rows
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "row": row = [:]
        case "c": cellIndex = Self.columnIndex(attributes["r"] ?? ""); cellType = attributes["t"] ?? ""; value = ""
        case "v": inValue = true
        case "t": if cellType == "inlineStr" { inInlineText = true }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue || inInlineText { value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v": inValue = false
        case "t": inInlineText = false
        case "c":
            if let cellIndex {
                let text: String
                if cellType == "s", let index = Int(value), sharedStrings.indices.contains(index) { text = sharedStrings[index] }
                else { text = value }
                row[cellIndex] = text
            }
            cellIndex = nil
        case "row":
            if let last = row.keys.max() { rows.append((0...last).map { row[$0] ?? "" }) }
        default: break
        }
    }
    private static func columnIndex(_ reference: String) -> Int? {
        let letters = reference.prefix(while: { $0.isLetter })
        guard !letters.isEmpty else { return nil }
        return letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }
}
