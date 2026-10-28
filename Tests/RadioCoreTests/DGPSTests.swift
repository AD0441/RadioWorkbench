import Foundation
import Testing
@testable import RadioCore

private struct DGPSManifest: Decodable {
    struct Fixture: Decodable { let file: String; let bit_rate: Int; let accepted: Int }
    let wire_bits: String
    let fixtures: [Fixture]
}
private struct DGPSOracle: Decodable {
    struct Frame: Decodable {
        struct Satellite: Decodable { let ident: Int; let udre: Int; let iod: Int; let prc: Double; let rrc: Double }
        let type: Int; let station_id: Int; let zcount: Double; let seqnum: Int
        let length: Int; let station_health: Int; let satellites: [Satellite]
    }
    let expected_frames: Int
    let first_frames: [Frame]
}
private func dgpsFixtureURL(_ name: String, extension ext: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
}
private func dgpsManifest() throws -> DGPSManifest {
    try JSONDecoder().decode(DGPSManifest.self, from: Data(contentsOf: dgpsFixtureURL("dgps-manifest", extension: "json")))
}
private func dgpsOracle() throws -> DGPSOracle {
    try JSONDecoder().decode(DGPSOracle.self, from: Data(contentsOf: dgpsFixtureURL("dgps-gpsd-oracle", extension: "json")))
}
private func dgpsReferenceBits() throws -> [Bool] {
    let data = try Data(contentsOf: dgpsFixtureURL("dgps-gpsd-sample", extension: "rtcm2"))
    var start = 0
    while start < data.count, data[start] == 35 {
        start = try #require(data[start...].firstIndex(of: 10)) + 1
    }
    // Magnavox serial format carries six on-air bits, earliest in the LSB.
    // It is not a WAV: the audio tests below independently modulate these bits.
    return data[start...].filter { $0 & 0xc0 == 0x40 }.flatMap { byte in
        (0..<6).map { byte & (1 << $0) != 0 }
    }
}
private func dgpsDecodeBits(_ bits: [Bool]) -> [DGPSReception] {
    var receiver = DGPSRTCMReceiver(), frames: [DGPSReception] = []
    for (index, bit) in bits.enumerated() {
        if let frame = receiver.push(bit: bit, time: Double(index) / 200, bitRate: 200) { frames.append(frame) }
    }
    return frames
}

@Test(arguments: [false, true]) func dgpsIndependentGPSDReferenceAndPolarity(_ complement: Bool) throws {
    let bits = try dgpsReferenceBits(), expected = try dgpsOracle()
    let frames = dgpsDecodeBits(bits.map { $0 != complement })
    #expect(frames.count == expected.expected_frames)
    for (actual, oracle) in zip(frames, expected.first_frames) {
        #expect(actual.stationID == oracle.station_id && actual.messageType == oracle.type)
        #expect(abs(actual.zCountSeconds - oracle.zcount) < 1e-8 && actual.sequence == oracle.seqnum)
        #expect(actual.stationHealth == oracle.station_health && actual.payloadWords.count == oracle.length)
        #expect(actual.corrections.count == oracle.satellites.count)
        for (correction, satellite) in zip(actual.corrections, oracle.satellites) {
            #expect(correction.satelliteID == satellite.ident && correction.udre == satellite.udre && correction.issueOfData == satellite.iod)
            #expect(abs(correction.pseudorangeMeters - satellite.prc) < 1e-8)
            #expect(abs(correction.rangeRateMetersPerSecond - satellite.rrc) < 1e-8)
        }
    }
}

@Test func dgpsChainedParityRejectsEverySingleBitChange() throws {
    var shift: UInt32 = 0, header: UInt32?
    for bit in try dgpsReferenceBits() {
        shift = (shift << 1) | (bit ? 1 : 0)
        if let data = DGPSParity.recoveredData(shift), data >> 16 == 0x66 { header = shift; break }
    }
    let word = try #require(header)
    #expect(DGPSParity.recoveredData(word) != nil)
    for bit in 0..<32 { #expect(DGPSParity.recoveredData(word ^ (1 << bit)) == nil) }
}

@Test(arguments: ["dgps_100_8000_mono_clean", "dgps_200_8000_impaired", "dgps_200_8000_bad_parity"])
func dgpsMSKAudioFixturesAndRecovery(_ name: String) throws {
    let fixture = try #require(dgpsManifest().fixtures.first { $0.file == name + ".wav" })
    let reader = try AudioFileReader(url: dgpsFixtureURL(name, extension: "wav"))
    var settings = DecoderSettings(); settings.frequency = 800
    let decoder = DGPSDecoder(sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() {
        for start in stride(from: 0, to: samples.count, by: 137) {
            decoder.process(Array(samples[start..<min(start + 137, samples.count)]))
        }
    }
    decoder.finish()
    #expect(decoder.acceptedFrames == fixture.accepted)
    #expect(decoder.receptions.map(\.messageType) == (fixture.accepted == 3 ? [16, 3, 6] : [3, 6]))
    #expect(decoder.receptions.allSatisfy { $0.stationID == 777 && $0.bitRate == fixture.bit_rate })
    if fixture.accepted == 3 { #expect(decoder.receptions.first?.specialMessage == "RWB DGPS TEST 014") }
    let position = try #require(decoder.receptions.first { $0.messageType == 3 }?.referencePosition)
    #expect(abs(position.latitude + 33.45) < 1e-6)
    #expect(abs(position.longitude + 70.6667) < 1e-6)
    #expect(abs(position.ellipsoidHeightMeters - 500) < 0.02)
}

// Own continuous-phase transmitter for the *independently recorded* GPSD bits.
// No receiver helper or parity implementation is used to produce this audio.
private func dgpsAudio(_ bits: [Bool], sampleRate: Double, bitRate: Double = 200,
                       center: Double = 800, reverse: Bool = false) -> [Float] {
    var phase = 0.713, output = [Float](repeating: 0, count: Int(sampleRate * 0.237919))
    let samples = Int(ceil(Double(bits.count) * sampleRate / bitRate))
    for index in 0..<samples {
        let bit = bits[min(bits.count - 1, Int(Double(index) * bitRate / sampleRate))]
        let delta = ((bit != reverse) ? 1.0 : -1.0) * bitRate / 4
        output.append(Float(0.58 * sin(phase)))
        phase += 2 * .pi * (center + delta) / sampleRate
        if phase >= 2 * .pi { phase -= 2 * .pi }
    }
    output += Array(repeating: 0, count: Int(sampleRate * 0.2))
    return output
}

@Test(arguments: [8000.0, 44100, 48000, 96000]) func dgpsIndependentMSKAtDeviceRates(_ sampleRate: Double) throws {
    // The first complete GPSD frame ends at bit401. Leading garbage is intentional.
    let bits = Array(try dgpsReferenceBits().prefix(401))
    var settings = DecoderSettings(); settings.frequency = 800; settings.dgpsRate = .bps200
    let decoder = DGPSDecoder(sampleRate: sampleRate, settings: settings)
    let samples = dgpsAudio(bits, sampleRate: sampleRate, center: 794, reverse: true)
    for start in stride(from: 0, to: samples.count, by: 113) {
        decoder.process(Array(samples[start..<min(start + 113, samples.count)]))
    }
    decoder.finish()
    #expect(decoder.acceptedFrames == 1)
    let frame = try #require(decoder.receptions.first)
    #expect(frame.messageType == 9 && frame.stationID == 268 && abs(frame.zCountSeconds - 249.6) < 1e-8)
    #expect(frame.corrections.map(\.satelliteID) == [13, 2, 8])
}

@Test func dgpsRejectsSilenceTonesNoiseWrongRateAndTruncation() throws {
    var settings = DecoderSettings(); settings.frequency = 800; settings.dgpsRate = .bps100
    let bits = Array(try dgpsReferenceBits().prefix(401))
    let wrongRate = DGPSDecoder(sampleRate: 8000, settings: settings)
    wrongRate.process(dgpsAudio(bits, sampleRate: 8000)); wrongRate.finish()
    #expect(wrongRate.acceptedFrames == 0)
    let truncated = DGPSDecoder(sampleRate: 8000, settings: settings)
    truncated.process(dgpsAudio(Array(bits.dropLast(50)), sampleRate: 8000, bitRate: 100))
    truncated.finish(); #expect(truncated.acceptedFrames == 0)
    for kind in 0..<3 {
        let decoder = DGPSDecoder(sampleRate: 8000, settings: settings)
        var random: UInt64 = 823200
        let samples: [Float] = (0..<32000).map { index in
            random = random &* 6364136223846793005 &+ 1
            if kind == 0 { return 0 }
            if kind == 1 { return Float(0.5 * sin(2 * .pi * 800 * Double(index) / 8000)) }
            return Float(Double(random >> 40) / Double(1 << 24) - 0.5)
        }
        decoder.process(samples); decoder.finish()
        #expect(decoder.acceptedFrames == 0 && decoder.text.isEmpty)
    }
}

@Test func dgpsTrailingSilenceDoesNotInventFramesAndHistoryIsBounded() throws {
    let bits = Array(try dgpsReferenceBits().prefix(401))
    var settings = DecoderSettings(); settings.frequency = 800; settings.dgpsRate = .bps200
    let decoder = DGPSDecoder(sampleRate: 8000, settings: settings)
    let samples = dgpsAudio(bits, sampleRate: 8000)
    for _ in 0..<70 { decoder.process(samples) }
    #expect(decoder.acceptedFrames == 70 && decoder.receptions.count == 64)
    decoder.process(Array(repeating: 0, count: 32000)); decoder.finish()
    #expect(decoder.acceptedFrames == 70 && decoder.text.utf8.count <= 65536)
    let copy = try JSONDecoder().decode([DGPSReception].self, from: JSONEncoder().encode(decoder.receptions))
    #expect(copy == decoder.receptions)
}

@Test func dgpsDoesNotInventCoordinatesAndEscapesControlBytes() {
    let zero = DGPSReception(sampleOffsetSeconds: 0, bitRate: 100, stationID: 0, messageType: 3,
                             zCountSeconds: 0, sequence: 0, stationHealth: 6, payloadWords: [0, 0, 0, 0])
    #expect(zero.referencePosition == nil)
    #expect(zero.monitorLine.contains("sin supervisión"))
    let control = DGPSReception(sampleOffsetSeconds: 0, bitRate: 100, stationID: 0, messageType: 16,
                                zCountSeconds: 0, sequence: 0, stationHealth: 7, payloadWords: [0x411b42, 0])
    #expect(control.specialMessage == "A\\x1BB")
    #expect(control.monitorLine.contains("NO OPERATIVA"))
}

@Test func dgpsRejectsParityValidIllegalNullLengthAndReservedZCount() {
    // Independently encoded with the Python transmitter/Table20-XIV equations.
    // Both have valid word parity; semantic header bounds must still reject them.
    let nullWithTwoPayloadWords = "11100110011110010011110110001100010000000101001100010000010010101010101010101010101010010101010101010101010101010101101010"
    let zCount6000 = "11100110011011110011110110101010101110111000001100001000011100010000010100001001000011000001"
    for bits in [nullWithTwoPayloadWords, zCount6000] {
        #expect(dgpsDecodeBits(bits.map { $0 == "1" }).isEmpty)
    }
}
