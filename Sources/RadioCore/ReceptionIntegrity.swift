import Foundation

/// Counters published by a decoder, distinct from transmitted/lost messages.
public struct ReceptionIntegrity: Codable, Equatable, Sendable {
    public let check: String
    public let unit: String
    public let accepted: Int
    public let rejected: Int?
    public let synchronized: Bool?
    public let note: String
    public init(check: String, unit: String, accepted: Int, rejected: Int? = nil, synchronized: Bool? = nil, note: String) {
        self.check = check; self.unit = unit; self.accepted = accepted; self.rejected = rejected; self.synchronized = synchronized; self.note = note
    }
}
