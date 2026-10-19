import Foundation

/// Compile with Sources/RadioCore/DigitalVoice.swift. Reads an offline console log,
/// verifies its independently published identity, and emits no local paths.
@main
struct DMRConsoleProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DMRConsoleProbe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Supply one offline DSD-neo stderr log."])
        }
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        var results: [[String: Any]] = []
        for size in [1, 7, 137, 8192] {
            var parser = DMRLogParser()
            let instant = Date(timeIntervalSince1970: 1_700_000_000)
            for offset in stride(from: 0, to: input.count, by: size) {
                parser.consume(input.subdata(in: offset..<min(offset + size, input.count)), at: instant)
            }
            parser.finish(at: instant)
            let slot = parser.status.slots[0]
            precondition(slot.sourceID == 3_025_209 && slot.targetID == 9_990)
            precondition(slot.colorCode == 7 && slot.callKind == "Individual")
            precondition(parser.status.slots[1].sourceID == nil && parser.status.slots[1].targetID == nil)
            precondition(parser.status.rejectedLines > 0)
            results.append(["fragment_bytes": size, "slot": slot.slot,
                            "source": slot.sourceID!, "target": slot.targetID!,
                            "color_code": slot.colorCode!, "call_kind": slot.callKind!,
                            "rejected_error_lines": parser.status.rejectedLines,
                            "unknown_slot2_identity": true])
        }
        let report: [String: Any] = ["probe": "Actual DSD-neo 2.10.0 stderr → current DMRLogParser",
                                     "checks_passed": results.count, "cases": results,
                                     "limit": "Console values are not independently CRC-verified."]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
