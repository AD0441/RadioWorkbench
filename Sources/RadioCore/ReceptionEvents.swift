import Foundation

public enum ReceptionEventSource: String, Codable, Sendable {
    case audioFile, audioLive, networkAudio, internet, imported
}

public struct ReceptionEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let source: String
    public var sourceKind: ReceptionEventSource
    public let protocolName: String
    public let entityID: String
    public let receivedAt: Date
    public let observedAt: Date?
    public let importedAt: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let message: String
    /// An adapter's claim; import does not independently verify a protocol CRC.
    public let integrity: String
    public init(id: String, source: String, sourceKind: ReceptionEventSource, protocolName: String,
                entityID: String, receivedAt: Date = Date(), observedAt: Date? = nil, importedAt: Date? = nil,
                latitude: Double? = nil, longitude: Double? = nil, message: String, integrity: String) {
        self.id = id; self.source = source; self.sourceKind = sourceKind; self.protocolName = protocolName
        self.entityID = entityID; self.receivedAt = receivedAt; self.observedAt = observedAt
        self.importedAt = importedAt
        self.latitude = latitude; self.longitude = longitude; self.message = message; self.integrity = integrity
    }
    public var location: RadioLocation? {
        guard let latitude, let longitude else { return nil }
        return RadioLocation(latitude: latitude, longitude: longitude)
    }
    public var trackID: String { sourceKind.rawValue + "|" + source + "|" + protocolName + "|" + entityID + (sourceKind == .imported ? "|" + id.split(separator: "|").prefix(2).joined(separator: "|") : "") }
    public func validated(now: Date = Date()) throws {
        guard !id.isEmpty, id.utf8.count <= 256, !source.isEmpty, source.utf8.count <= 300,
              !protocolName.isEmpty, protocolName.utf8.count <= 40, !entityID.isEmpty, entityID.utf8.count <= 128,
              message.utf8.count <= 8192, integrity.utf8.count <= 300,
              receivedAt.timeIntervalSince1970.isFinite, receivedAt >= Date(timeIntervalSince1970: -2_208_988_800),
              receivedAt <= now.addingTimeInterval(300),
              observedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= Date(timeIntervalSince1970: -2_208_988_800) && $0 <= now.addingTimeInterval(300) }) ?? true,
              importedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= Date(timeIntervalSince1970: -2_208_988_800) && $0 <= now.addingTimeInterval(300) }) ?? true,
              (latitude == nil && longitude == nil) || location != nil else { throw RadioEventError.invalidEvent }
    }
}

public enum RadioEventError: LocalizedError {
    case invalidEvent, invalidDocument
    public var errorDescription: String? {
        switch self {
        case .invalidEvent: "El evento contiene coordenadas, fecha o campos no válidos. No se importó el lote."
        case .invalidDocument: "Se requiere RadioWorkbench Events v1: un documento JSON con hasta 5.000 eventos y un máximo de 10 MB."
        }
    }
}

public struct ReceptionEventDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let events: [ReceptionEvent]
    public init(events: [ReceptionEvent]) { schemaVersion = 1; self.events = events }
    public static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        guard data.count <= 10_000_000 else { throw RadioEventError.invalidDocument }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let document: Self
        do { document = try decoder.decode(Self.self, from: data) }
        catch { throw RadioEventError.invalidDocument }
        guard document.schemaVersion == 1, document.events.count <= 5000,
              Set(document.events.map(\.id)).count == document.events.count else { throw RadioEventError.invalidDocument }
        for event in document.events { try event.validated(now: now) }
        return document
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Bounded traces never bridge a source or a gap over 30 minutes, nor draw a
/// spurious line across the entire map at the antimeridian.
public enum ReceptionTrace {
    public static func segments(_ events: [ReceptionEvent]) -> [[ReceptionEvent]] {
        let grouped = Dictionary(grouping: events.filter { $0.location != nil && (($0.sourceKind != .audioFile && $0.sourceKind != .imported) || $0.observedAt != nil) }, by: \.trackID)
        var result: [[ReceptionEvent]] = []
        for points in grouped.values {
            var segment: [ReceptionEvent] = []
            for point in points.sorted(by: { ($0.observedAt ?? $0.receivedAt) < ($1.observedAt ?? $1.receivedAt) }).suffix(100) {
                if let last = segment.last,
                   abs(point.longitude! - last.longitude!) > 180 ||
                    (point.observedAt ?? point.receivedAt).timeIntervalSince(last.observedAt ?? last.receivedAt) > 1800 {
                    if segment.count > 1 { result.append(segment) }; segment = []
                }
                segment.append(point)
            }
            if segment.count > 1 { result.append(segment) }
        }
        return result
    }
}
