import Foundation
import Testing
@testable import RadioCore

private struct PacketManifest: Decodable {
    struct Fixture: Decodable {
        let file: String
        let expected_text: String
        let accepted: Int
        let rejected_crc: Int
        let wire_bits: String
    }
    let valid_frame_hex: String
    let fixtures: [Fixture]
}

private func packetManifest() throws -> PacketManifest {
    let url = try #require(Bundle.module.url(forResource: "packet-manifest", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(PacketManifest.self, from: Data(contentsOf: url))
}

@Test func packetKnownCRCCheckValue() {
    #expect(PacketFCS.residue(Array("123456789".utf8)) ^ 0xFFFF == 0x906E)
}

@Test(arguments: ["packet_8000_mono_clean", "packet_8000_mono_crc_bad", "packet_8000_mono_resync"])
func packetIndependentHDLCBitVectors(_ name: String) throws {
    let fixture = try #require(packetManifest().fixtures.first { $0.file == name + ".wav" })
    let receiver = PacketHDLCReceiver()
    for character in fixture.wire_bits { receiver.push(bit: character == "1") }
    #expect(receiver.text == fixture.expected_text)
    #expect(receiver.accepted == fixture.accepted)
    #expect(receiver.rejectedCRC == fixture.rejected_crc)
    #expect(receiver.rejectedFormat == 0)
    if let frame = receiver.frames.first {
        #expect(frame.destination.label == "APRS")
        #expect(frame.source.label == "TEST-1")
        #expect(frame.path.map(\.label) == ["WIDE1-1", "WIDE2-2"])
        #expect(frame.path.map(\.repeated) == [true, false])
    }
}

@Test(arguments: ["packet_8000_mono_clean", "packet_8000_mono_noisy", "packet_8000_mono_offset", "packet_8000_mono_drift", "packet_8000_mono_crc_bad", "packet_44100_stereo_clean", "packet_8000_mono_resync"])
func packetIndependentAudioFixtures(_ name: String) throws {
    let fixture = try #require(packetManifest().fixtures.first { $0.file == name + ".wav" })
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url)
    var settings = DecoderSettings(); settings.frequency = 1700
    let decoder = PacketAFSK1200Decoder(sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() {
        for start in stride(from: 0, to: samples.count, by: 137) {
            decoder.process(Array(samples[start..<min(start + 137, samples.count)]))
        }
    }
    #expect(decoder.text == fixture.expected_text)
    #expect(decoder.acceptedFrames == fixture.accepted)
    #expect(decoder.rejectedCRC == fixture.rejected_crc)
}

@Test(arguments: [AudioChannelSelection.mix, .channel(0), .channel(1)])
func packetOppositeStereoNeedsExplicitChannel(_ channel: AudioChannelSelection) throws {
    let url = try #require(Bundle.module.url(forResource: "packet_48000_stereo_opposite", withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url, channel: channel)
    var settings = DecoderSettings(); settings.frequency = 1700
    let decoder = PacketAFSK1200Decoder(sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() { decoder.process(samples) }
    #expect(decoder.acceptedFrames == (channel == .mix ? 0 : 1))
    #expect(decoder.text.isEmpty == (channel == .mix))
}

@Test func packetFramesAreBoundedAndAbortIsRecoverable() throws {
    let fixture = try #require(packetManifest().fixtures.first { $0.file == "packet_8000_mono_clean.wav" })
    let receiver = PacketHDLCReceiver()
    for bit in "01111110" { receiver.push(bit: bit == "1") }
    for _ in 0..<6000 { receiver.push(bit: false) }
    #expect(receiver.rejectedFormat == 1)
    for bit in "01111110111111111111111" { receiver.push(bit: bit == "1") }
    #expect(receiver.aborted == 1)
    for character in fixture.wire_bits { receiver.push(bit: character == "1") }
    #expect(receiver.accepted == 1)
    #expect(receiver.text == fixture.expected_text)
}

@Test func packetPayloadControlBytesAreVisible() {
    let address = PacketAX25Address(callsign: "TEST", ssid: 0, repeated: false)
    let frame = PacketAX25Frame(destination: address, source: address, path: [], control: 3,
                                protocolID: 0xF0, information: [65, 27, 10, 255])
    #expect(frame.monitorLine == "TEST>TEST:A\\x1B\\x0A\\xFF")
}

@Test func packetMalformedAddressAndControlAreRejected() throws {
    let hex = try packetManifest().valid_frame_hex
    let pairs = stride(from: 0, to: hex.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
    }
    var bytes = try pairs.map { try #require($0) }
    bytes.removeLast(2)
    #expect(PacketAX25Frame.parse(bytes) != nil)
    #expect(PacketAX25Frame.parse(Array(bytes.prefix(12))) == nil)
    var invalid = bytes; invalid[0] |= 1
    #expect(PacketAX25Frame.parse(invalid) == nil)
    invalid = bytes; invalid[27] &= 0xFE
    #expect(PacketAX25Frame.parse(invalid) == nil)
    invalid = bytes; invalid[28] = 0x01 // supervisory frame, not UI
    #expect(PacketAX25Frame.parse(invalid) == nil)
    invalid = bytes; invalid[28] = 0x13 // UI with poll/final bit
    #expect(PacketAX25Frame.parse(invalid) != nil)
}

@Test func packetMonitorRetainsBoundedRecentFrames() throws {
    let fixture = try #require(packetManifest().fixtures.first { $0.file == "packet_8000_mono_clean.wav" })
    let receiver = PacketHDLCReceiver()
    for _ in 0..<70 {
        for character in fixture.wire_bits { receiver.push(bit: character == "1") }
    }
    #expect(receiver.accepted == 70)
    #expect(receiver.frames.count == 64)
    #expect(receiver.text.utf8.count <= 65536)
}

@Test func packetNoiseAndMissingClosingFlagProduceNoMessage() throws {
    let fixture = try #require(packetManifest().fixtures.first { $0.file == "packet_8000_mono_clean.wav" })
    let receiver = PacketHDLCReceiver()
    for character in fixture.wire_bits.dropLast(64) { receiver.push(bit: character == "1") }
    #expect(receiver.accepted == 0)
    #expect(receiver.text.isEmpty)
    var settings = DecoderSettings(); settings.frequency = 1700
    let decoder = PacketAFSK1200Decoder(sampleRate: 8000, settings: settings)
    var random: UInt32 = 0x12002200
    var noise = [Float](repeating: 0, count: 257)
    for _ in 0..<64 {
        for index in noise.indices {
            random = random &* 1664525 &+ 1013904223
            noise[index] = (Float(random >> 8) / 16777216 - 0.5) * 0.4
        }
        decoder.process(noise)
    }
    #expect(decoder.acceptedFrames == 0)
    #expect(decoder.text.isEmpty)
}

@Test func packetEngineIntegrationUsesTheNativeDecoder() throws {
    let fixture = try #require(packetManifest().fixtures.first { $0.file == "packet_8000_mono_clean.wav" })
    let url = try #require(Bundle.module.url(forResource: "packet_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url)
    var settings = DecoderSettings(); settings.frequency = 1700
    let engine = try DecoderEngine(mode: .packet, sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() { engine.process(samples) }
    engine.finish()
    #expect(engine.text == fixture.expected_text)
    #expect(engine.status.contains("1 CRC válidos"))
}

@Test func packetEngineRejectsAliasedToneSettings() {
    var settings = DecoderSettings(); settings.frequency = 1700
    #expect(throws: RadioError.self) { try DecoderEngine(mode: .packet, sampleRate: 4000, settings: settings) }
    settings.frequency = 3600
    #expect(throws: RadioError.self) { try DecoderEngine(mode: .packet, sampleRate: 8000, settings: settings) }
    settings.frequency = 400
    #expect(throws: RadioError.self) { try DecoderEngine(mode: .packet, sampleRate: 8000, settings: settings) }
}
