import Foundation

public enum ListeningOutcome: String, Codable, CaseIterable, Sendable {
    case heard, notHeard, uncertain
    public var title: String {
        switch self { case .heard: "Escuchada"; case .notHeard: "No escuchada"; case .uncertain: "Dudosa" }
    }
}

public enum ListeningOrigin: String, Codable, CaseIterable, Sendable {
    case local, remote, recording
    public var title: String {
        switch self { case .local: "Antena local"; case .remote: "WebSDR / receptor remoto"; case .recording: "Grabación / fecha conocida" }
    }
}

public enum ListeningEvidence: String, CaseIterable, Sendable {
    case manual = "Anotación manual", audio = "Audio adjunto", event = "Evento vinculado"
}

/// A historical snapshot: changing the current station profile never moves an old reception.
public struct ListeningStation: Codable, Equatable, Sendable {
    public var location: RadioLocation?
    public var receiver: String
    public var antenna: String
    public var origin: ListeningOrigin
    public init(location: RadioLocation?, receiver: String = "", antenna: String = "", origin: ListeningOrigin = .local) {
        self.location = location; self.receiver = receiver; self.antenna = antenna; self.origin = origin
    }
}

public struct ListeningForecast: Codable, Equatable, Sendable {
    public var model: String
    public var computedAt: Date
    public var assumptions: String
    public init(model: String, computedAt: Date, assumptions: String) {
        self.model = model; self.computedAt = computedAt; self.assumptions = assumptions
    }
}

public struct ListeningObservation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var observedAt: Date
    public var endedAt: Date?
    public var stationName: String
    public var frequencyHz: Double
    public var modulation: String
    public var broadcast: BroadcastEntry?
    public var scheduleSeason: String?
    public var scheduleFetchedAt: Date?
    public var transmitter: RadioLocation?
    public var transmitterName: String
    public var transmitterSource: String
    public var receivingStation: ListeningStation
    public var outcome: ListeningOutcome
    public var quality: Int?
    public var notes: String
    public var audioSessionID: UUID?
    public var eventID: UUID?
    public var forecast: ListeningForecast?
    public var trashedAt: Date?
    public var isTrashed: Bool { trashedAt != nil }
    public var evidence: ListeningEvidence { eventID != nil ? .event : audioSessionID != nil ? .audio : .manual }
    public var distanceKm: Double? { transmitter.flatMap { tx in receivingStation.location.map { tx.distance(to: $0) } } }
    /// Direction from the receiving antenna toward the transmitter.
    public var bearing: Double? { receivingStation.location.flatMap { rx in transmitter.map { rx.bearing(to: $0) } } }
    public var mapSegments: [[RadioLocation]] {
        guard let tx = transmitter, let rx = receivingStation.location else { return [] }
        return tx.greatCircleSegments(to: rx)
    }
    public var band: String {
        let kHz = frequencyHz / 1000
        if let band = BroadcastEntry.bands.first(where: { ($0.1...$0.2).contains(kHz) }) { return band.0 }
        switch frequencyHz { case ..<300_000: return "OL"; case ..<3_000_000: return "OM"; case ..<30_000_000: return "HF"; case ..<300_000_000: return "VHF"; default: return "UHF+" }
    }
    public init(id: UUID = UUID(), observedAt: Date = Date(), stationName: String, frequencyHz: Double,
                modulation: String, receivingStation: ListeningStation, outcome: ListeningOutcome = .heard) {
        self.id = id; self.createdAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        self.observedAt = Date(timeIntervalSince1970: floor(observedAt.timeIntervalSince1970))
        self.stationName = stationName; self.frequencyHz = frequencyHz; self.modulation = modulation
        self.receivingStation = receivingStation; self.outcome = outcome
        self.transmitterName = ""; self.transmitterSource = ""; self.notes = ""
    }
    public var isValid: Bool {
        func validDate(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite && (-62_135_596_800...253_402_300_799).contains(date.timeIntervalSince1970) }
        func validLocation(_ value: RadioLocation?) -> Bool { value.map { RadioLocation(latitude: $0.latitude, longitude: $0.longitude) != nil } ?? true }
        let texts = [stationName, modulation, transmitterName, transmitterSource, receivingStation.receiver, receivingStation.antenna]
        return !stationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && texts.allSatisfy { $0.count <= 300 } && notes.count <= 4000
            && frequencyHz.isFinite && (1...1_000_000_000_000).contains(frequencyHz)
            && validDate(createdAt) && validDate(observedAt) && (endedAt.map { validDate($0) && $0 >= observedAt } ?? true)
            && (scheduleFetchedAt.map(validDate) ?? true) && (trashedAt.map(validDate) ?? true)
            && (quality.map { (1...5).contains($0) } ?? true)
            && validLocation(transmitter) && validLocation(receivingStation.location)
            && (scheduleSeason?.count ?? 0) <= 80 && (broadcast?.raw.count ?? 0) <= 4000
            && (forecast.map { $0.model.count <= 200 && $0.assumptions.count <= 8000 && validDate($0.computedAt) } ?? true)
    }
}

extension RadioLocation {
    /// Bounded great-circle samples, split at the map seam rather than drawing across the world.
    public func greatCircleSegments(to target: RadioLocation) -> [[RadioLocation]] {
        let distance = self.distance(to: target), direction = bearing(to: target)
        let count = max(1, min(401, Int(ceil(distance / 100))))
        var segments: [[RadioLocation]] = [[self]]
        for index in 1...count {
            guard let next = index == count ? target : destination(km: min(20_000, distance * Double(index) / Double(count)), bearing: direction),
                  let previous = segments.last?.last else { continue }
            if abs(next.longitude - previous.longitude) > 180 {
                let eastward = previous.longitude > 0
                let unwrapped = next.longitude + (eastward ? 360 : -360)
                let boundary = eastward ? 180.0 : -180.0
                let fraction = (boundary - previous.longitude) / (unwrapped - previous.longitude)
                let latitude = previous.latitude + fraction * (next.latitude - previous.latitude)
                if let edge = RadioLocation(latitude: latitude, longitude: boundary),
                   let opposite = RadioLocation(latitude: latitude, longitude: -boundary) {
                    segments[segments.count - 1].append(edge); segments.append([opposite, next])
                }
            } else { segments[segments.count - 1].append(next) }
        }
        return segments.filter { $0.count > 1 }
    }
}

public struct ListeningFilter: Sendable {
    public var from: Date?
    public var through: Date?
    public var firstHour = 0
    public var lastHour = 23
    public var timeZone = TimeZone(secondsFromGMT: 0)!
    public var antenna = "Todas"
    public var band = "Todas"
    public var modulation = "Todos"
    public var origin: ListeningOrigin?
    public var evidence: ListeningEvidence?
    public init() {}
    public func includes(_ value: ListeningObservation) -> Bool {
        guard (0...23).contains(firstHour), (0...23).contains(lastHour), !value.isTrashed, from.map({ value.observedAt >= $0 }) ?? true,
              through.map({ value.observedAt <= $0 }) ?? true,
              antenna == "Todas" || value.receivingStation.antenna == antenna,
              band == "Todas" || value.band == band,
              modulation == "Todos" || value.modulation == modulation,
              origin == nil || value.receivingStation.origin == origin,
              evidence == nil || value.evidence == evidence else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: value.observedAt)
        return firstHour <= lastHour ? (firstHour...lastHour).contains(hour) : hour >= firstHour || hour <= lastHour
    }
}
