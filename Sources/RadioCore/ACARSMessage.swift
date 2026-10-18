import Foundation

public struct ACARSMessage: Decodable, Encodable, Identifiable, Sendable {
    public struct AircraftPosition: Codable, Sendable {
        public let latitude: Double, longitude: Double
        public let altitudeFeet: Int
    }
    public let applicationText: String?
    public let applicationJSON: String?
    public let applicationStatus: Int?
    public let aircraftPosition: AircraftPosition?
    public let id: UUID
    public let timestamp: Double
    public let mode: String
    public let registration: String
    public let ack: String
    public let label: String
    public let block: String
    public let payload: String
    public let endBlock: Int
    public let parityCorrections: Int
    public let levelDB: Double
    private enum CodingKeys: String, CodingKey { case timestamp, mode, registration, ack, label, block, payload, endBlock, parityCorrections, levelDB, applicationText, applicationJSON, applicationStatus, aircraftPosition }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applicationText = try c.decodeIfPresent(String.self, forKey: .applicationText)
        applicationJSON = try c.decodeIfPresent(String.self, forKey: .applicationJSON)
        applicationStatus = try c.decodeIfPresent(Int.self, forKey: .applicationStatus)
        let pos = try c.decodeIfPresent(AircraftPosition.self, forKey: .aircraftPosition)
        aircraftPosition = pos.flatMap { $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) ? $0 : nil }
        guard (applicationText?.utf8.count ?? 0) <= 65536, (applicationJSON?.utf8.count ?? 0) <= 65536 else { throw RadioError.invalidAudio }
        id = UUID(); timestamp = try c.decode(Double.self, forKey: .timestamp)
        mode = try c.decode(String.self, forKey: .mode)
        registration = try c.decode(String.self, forKey: .registration)
        ack = try c.decode(String.self, forKey: .ack); label = try c.decode(String.self, forKey: .label)
        block = try c.decode(String.self, forKey: .block); payload = try c.decode(String.self, forKey: .payload)
        endBlock = try c.decode(Int.self, forKey: .endBlock)
        parityCorrections = try c.decode(Int.self, forKey: .parityCorrections)
        levelDB = try c.decode(Double.self, forKey: .levelDB)
        guard timestamp.isFinite, levelDB.isFinite, mode.utf8.count == 1, registration.utf8.count <= 7,
              label.utf8.count <= 2, block.utf8.count == 1, payload.utf8.count <= 1024,
              (0...3).contains(parityCorrections), [3,23].contains(endBlock) else { throw RadioError.invalidAudio }
    }
    public var decodedAt: Date { Date(timeIntervalSince1970: timestamp) }
    public var isDownlink: Bool { block.first.map { "0123456789".contains($0) } ?? false }
    public var tail: String { registration.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
    public var messageNumber: String { isDownlink && payload.count >= 10 ? String(payload.prefix(4)) : "" }
    public var flight: String { isDownlink && payload.count >= 10 ? String(payload.dropFirst(4).prefix(6)).trimmingCharacters(in: .whitespaces) : "" }
    public var body: String { isDownlink && payload.count >= 10 ? String(payload.dropFirst(10)) : payload }
    public var monitorLine: String { "\(tail) · \(flight.isEmpty ? "sin vuelo" : flight) · \(label) · bloque \(block)\n\(body)\n" }
}
