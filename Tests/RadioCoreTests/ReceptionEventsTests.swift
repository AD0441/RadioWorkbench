import Foundation
import Testing
@testable import RadioCore

private func receptionEvent(_ id: String, lon: Double = -70, time: Date = Date(), source: String = "test", lat: Double = -33) -> ReceptionEvent {
    ReceptionEvent(id: id, source: source, sourceKind: .internet, protocolName: "TEST", entityID: "SYNTH", receivedAt: time,
                   latitude: lat, longitude: lon, message: "Synthetic test", integrity: "unverified")
}
@Test func receptionEventsValidateWholeDocumentAndKeepProvenance() throws {
    let event = receptionEvent("one")
    let document = try ReceptionEventDocument.decode(ReceptionEventDocument(events: [event]).encoded())
    #expect(document.events[0].source == "test" && document.events[0].observedAt == nil)
    #expect(throws: RadioEventError.self) { try ReceptionEventDocument.decode(ReceptionEventDocument(events: [event, event]).encoded()) }
    #expect(throws: RadioEventError.self) { try receptionEvent("bad", lat: 91).validated() }
    #expect(throws: RadioEventError.self) { try receptionEvent("future", time: Date().addingTimeInterval(3600)).validated() }
    #expect(throws: RadioEventError.self) { try ReceptionEventDocument.decode(Data("{\"schemaVersion\":99,\"events\":[]}".utf8)) }
}
@Test func receptionTracesSeparateSourcesGapsAndAntimeridian() {
    let now = Date()
    let a = receptionEvent("a", lon: 179, time: now.addingTimeInterval(-5))
    let b = receptionEvent("b", lon: -179, time: now)
    #expect(ReceptionTrace.segments([a, b]).isEmpty)
    let c = receptionEvent("c", time: now.addingTimeInterval(-60))
    let d = receptionEvent("d", lon: -70.1, time: now)
    #expect(ReceptionTrace.segments([c, d]).count == 1)
    #expect(ReceptionTrace.segments([c, receptionEvent("e", time: now, source: "other")]).isEmpty)
    #expect(ReceptionTrace.segments([c, receptionEvent("f", time: now.addingTimeInterval(3600))]).isEmpty)
}
