import Foundation

public struct BroadcastEntry: Identifiable, Codable, Hashable, Sendable {
    public let frequencyKHz: Double
    public let time: String
    public let days: String
    public let country: String
    public let station: String
    public let language: String
    public let target: String
    public let site: String
    public let persistence: Int
    public let startDate: String
    public let stopDate: String
    public let raw: String
    public var id: String { raw }
    public var isUtility: Bool { persistence >= 90 || (language.hasPrefix("-") && language != "-DRM") }
    public var band: String {
        switch frequencyKHz {
        case ..<300: "OL"
        case ..<3000: "OM"
        case ..<30000: "OC"
        default: "VHF"
        }
    }
    public var broadcastBand: String {
        for (name, low, high) in Self.bands where (low...high).contains(frequencyKHz) { return name }
        return band
    }
    public static let bands: [(String, Double, Double)] = [
        ("120 m",2300,2495),("90 m",3200,3400),("75 m",3900,4000),
        ("60 m",4750,5060),("49 m",5900,6200),("41 m",7200,7450),
        ("31 m",9400,9900),("25 m",11600,12100),("22 m",13570,13870),
        ("19 m",15100,15800),("16 m",17480,17900),("15 m",18900,19020),
        ("13 m",21450,21850),("11 m",25670,26100)
    ]
    public var modulation: String {
        if language == "-DRM" || station.localizedCaseInsensitiveContains("DRM") { return "DRM · I/Q o FI" }
        if days.contains("LSB") { return "LSB" }
        if days.contains("USB") || language == "-HF" { return "USB" }
        if language == "-CW" { return "CW / USB" }
        return isUtility ? "Consultar tipo de señal" : "AM · 6–10 kHz"
    }
    public var tuningSuggestion: String {
        if modulation.hasPrefix("DRM") { return "DRM · ancho variable; mantener el canal completo" }
        if modulation.hasPrefix("CW") { return "CW · USB · filtro sugerido 400–600 Hz" }
        if modulation == "USB" || modulation == "LSB" { return "\(modulation) · filtro sugerido 2,4–2,7 kHz" }
        if modulation.hasPrefix("AM") { return "AM · audio sugerido 6–10 kHz; confirmar emisión" }
        return "Modo y ancho dependen de la señal; verificar al escuchar"
    }
}

public struct BroadcastSnapshot: Codable, Sendable {
    public let entries: [BroadcastEntry]
    public let reference: BroadcastReference
    public let season: String
    public let sourceURL: URL
    public let fetchedAt: Date
    public let sourceModifiedAt: Date?
    public let skippedRows: Int
    public init(entries: [BroadcastEntry], reference: BroadcastReference, season: String, sourceURL: URL, fetchedAt: Date, sourceModifiedAt: Date?, skippedRows: Int) {
        self.entries = entries; self.reference = reference; self.season = season
        self.sourceURL = sourceURL; self.fetchedAt = fetchedAt; self.sourceModifiedAt = sourceModifiedAt; self.skippedRows = skippedRows
    }
}
