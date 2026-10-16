import Foundation
import Testing
import CoreGraphics
import ImageIO
@testable import RadioCore
@testable import RadioWorkbench

private func extraFixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
}
private func decodePager(samples: [Float], settings: DecoderSettings = DecoderSettings()) throws -> MultimonSnapshot {
    let process = try MultimonProcess(mode: .pocsag, settings: settings)
    defer { process.cancel() }
    for offset in stride(from: 0, to: samples.count, by: 997) { try process.write(Array(samples[offset..<min(samples.count, offset + 997)])) }
    return try process.finish()
}
private func fixtureSamples(_ name: String) throws -> [Float] {
    let reader = try AudioFileReader(url: extraFixture(name))
    var result: [Float] = []
    while let samples = try reader.next() { result += samples }
    return result
}

@Test(arguments: [512, 1200, 2400]) func pagerDecodesIndependentSyntheticFramesAtAllThreeRates(_ baud: Int) throws {
    let samples = try fixtureSamples("pocsag_\(baud)_22050_discriminator_clean")
    let normal = try decodePager(samples: samples), reversed = try decodePager(samples: samples.map { -$0 })
    for result in [normal, reversed] {
        #expect(result.records.contains { $0.decoder == "POCSAG\(baud)" && $0.address == 123456 && $0.function == 3 && $0.body.contains("CQ RADIOWORKBENCH \(baud)") })
        #expect(result.records.allSatisfy { $0.kind != "TONO" })
    }
}

@Test func pagerBCHCorrectsTwoErrorsAndStrictModeRejectsTheDamagedWord() throws {
    var samples = try fixtureSamples("pocsag_1200_22050_discriminator_clean")
    for bit in [576 + 32 + 32 + 10, 576 + 32 + 32 + 20] {
        let start = Int(ceil(Double(bit) * 22050 / 1200)), end = Int(ceil(Double(bit + 1) * 22050 / 1200))
        for index in start..<end { samples[index] *= -1 }
    }
    let corrected = try decodePager(samples: samples)
    #expect(corrected.records.contains { $0.body.contains("CQ RADIOWORKBENCH 1200") })
    var strict = DecoderSettings(); strict.pagerCorrectionBits = 0
    let rejected = try decodePager(samples: samples, settings: strict)
    #expect(!rejected.records.contains { $0.body.contains("CQ RADIOWORKBENCH 1200") })
}

@Test func pagerSilenceAndRestartProduceNoFalseTextAndCancelStopsTheHelper() throws {
    #expect(try decodePager(samples: [Float](repeating: 0, count: 44_100)).records.isEmpty)
    let process = try MultimonProcess(mode: .pocsag, settings: DecoderSettings())
    process.cancel()
    let deadline = Date().addingTimeInterval(2)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    #expect(!process.isRunning)
}

@Test func selcallRecognizesZVEI1AndPreservesRawSpecialCodes() throws {
    let process = try MultimonProcess(mode: .fiveTones, settings: DecoderSettings())
    defer { process.cancel() }
    try process.write(fixtureSamples("selcall_zvei1_22050_12345"))
    let result = try process.finish()
    #expect(result.records.contains { $0.decoder == "ZVEI1" && $0.body == "12345" })
    let special = try #require(MultimonRecord.parse(Data("ZVEI1: 12E34".utf8), mode: .fiveTones, standard: .zvei1))
    #expect(special.body == "12E34")
    #expect(MultimonRecord.parse(Data("CCIR: 12345".utf8), mode: .fiveTones, standard: .zvei1) == nil)
}

@Test(arguments: FiveToneStandard.allCases) func selcallAllEightFamiliesReceiveTheirDistinctiveCodes(_ standard: FiveToneStandard) throws {
    var settings = DecoderSettings(); settings.fiveToneStandard = standard
    let process = try MultimonProcess(mode: .fiveTones, settings: settings)
    defer { process.cancel() }
    try process.write(fixtureSamples("selcall_\(standard.rawValue.lowercased())_22050_1abcd"))
    #expect(try process.finish().records.contains { $0.decoder == standard.rawValue && $0.body == "1ABCD" })
}

@Test func pagerMalformedOutputCannotInventIdentifiersOrRetainUnboundedText() {
    let invalid = [#"{"demod_name":"POCSAG1200","address":true,"function":3,"alpha":"bad"}"#,
        #"{"demod_name":"POCSAG1200","address":3.5,"function":3,"alpha":"bad"}"#,
        #"{"demod_name":"POCSAG1200","address":123456,"function":5,"alpha":"bad"}"#]
    for line in invalid { #expect(MultimonRecord.parse(Data(line.utf8), mode: .pocsag, standard: .zvei1) == nil) }
    let huge = #"{"demod_name":"POCSAG1200","address":123456,"function":3,"alpha":""# + String(repeating: "X", count: 9000) + "\"}"
    #expect(MultimonRecord.parse(Data(huge.utf8), mode: .pocsag, standard: .zvei1) == nil)
}

@Test(arguments: [(RTTYEncoding.ascii7, 75.0, 7), (.ascii8, 110.0, 8)])
func rttyASCIIFramingReadsSevenAndEightBitsWithoutITA2ShiftInterpretation(_ input: (RTTYEncoding, Double, Int)) throws {
    var settings = DecoderSettings(); settings.rttyEncoding = input.0; settings.baud = input.1; settings.frequency = 1500
    let decoder = try DecoderEngine(mode: .rtty, sampleRate: 8000, settings: settings)
    let samples = try fixtureSamples("rtty_ascii\(input.2)_8000_\(Int(input.1))baud")
    for offset in stride(from: 0, to: samples.count, by: 731) { decoder.process(Array(samples[offset..<min(samples.count, offset + 731)])) }
    decoder.finish()
    #expect(decoder.text == "CQ ASCII\(input.2) RADIOWORKBENCH\n")
}

@Test(arguments: [(HellVariant.feld, "feld", 1500.0), (.slow14, "slow14", 1500), (.slowFldigi, "slow_fldigi", 1500), (.x5, "x5", 1500), (.x9, "x9", 2000)])
func hellPulseVariantsKeepSenderGlyphContrastAndHaveBoundedVisualRaster(_ input: (HellVariant, String, Double)) throws {
    var settings = DecoderSettings(); settings.hellVariant = input.0; settings.frequency = input.2
    settings.threshold = 0.04; settings.imageStartSeconds = 0.2
    let decoder = try DecoderEngine(mode: .hell, sampleRate: 8000, settings: settings)
    let samples = try fixtureSamples("hell_\(input.1)_8000_cq_clean")
    for offset in stride(from: 0, to: samples.count, by: 613) { decoder.process(Array(samples[offset..<min(samples.count, offset + 613)])) }
    decoder.finish()
    let image = try #require(decoder.image)
    #expect(image.width >= 30 && image.height >= 28 && image.width <= 320 && image.height <= 224)
    #expect(image.rgb.count == image.width * image.height * 3)
    #expect(image.rgb.min()! < 100 && image.rgb.max()! > 240)
    let manifest = try #require(Bundle.module.url(forResource: "additional-modes-manifest", withExtension: "json", subdirectory: "Fixtures"))
    let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
    let files = try #require(root["files"] as? [String: [String: Any]])
    let columns = try #require(files["hell_\(input.1)_8000_cq_clean.wav"]?["columns"] as? [[Int]])
    // Hell has no character sync; compare the glyph after allowing the filter's vertical phase delay.
    let errors = (0...2).map { phase -> Double in
        var error = 0.0
        for (col, pixels) in columns.enumerated() {
            for row in 0..<14 {
                let y = 27 - (row + phase) % 14
                let actual = Double(image.rgb[(y * image.width + col * 2) * 3])
                error += abs(actual - (pixels[row] == 0 ? 255 : 0))
            }
        }
        return error / Double(columns.count * 14)
    }
    #expect(errors.min()! < 80)
    print("Hell \(input.1): error visual medio \(errors.min()!) /255")
    let directory = URL(fileURLWithPath: "/private/tmp/radioworkbench-hell-validation")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let provider = try #require(CGDataProvider(data: Data(image.rgb) as CFData))
    let cgImage = try #require(CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 24,
        bytesPerRow: image.width * 3, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = try #require(CGImageDestinationCreateWithURL(directory.appendingPathComponent("hell-\(input.1).png") as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(output, cgImage, nil); #expect(CGImageDestinationFinalize(output))
}

@Test func decoderProfilesFromOlderVersionsKeepTheirSettingsWhenNewModeFieldsAreMissing() throws {
    var settings = DecoderSettings(); settings.frequency = 1900; settings.sstvRobot36Compatibility = true; settings.audioChannel = .channel(1)
    var row = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    for key in ["pagerRate", "pagerCorrectionBits", "pagerShowEmpty", "fiveToneStandard", "rttyEncoding", "hellVariant"] { row.removeValue(forKey: key) }
    let decoded = try JSONDecoder().decode(DecoderSettings.self, from: JSONSerialization.data(withJSONObject: row))
    #expect(decoded.frequency == 1900 && decoded.audioChannel == .channel(1) && decoded.sstvRobot36Compatibility)
    #expect(decoded.pagerRate == .automatic && decoded.rttyEncoding == .ita2 && decoded.hellVariant == .feld)
}

private actor ExtraUpdateCollector {
    var final: RadioUpdate?
    func append(_ update: RadioUpdate) { if update.finished { final = update } }
}
@Test func pagerAppWorkerResamplesWAVAndPublishesStructuredRecords() async throws {
    let updates = ExtraUpdateCollector()
    try await RadioWorker().decodeFile(url: extraFixture("pocsag_1200_22050_discriminator_clean"), mode: .pocsag, settings: DecoderSettings()) { await updates.append($0) }
    let final = try #require(await updates.final)
    #expect(final.finished && final.progress == 1)
    #expect(final.multimonRecords.contains { $0.address == 123456 && $0.body.contains("CQ RADIOWORKBENCH 1200") })
}
