import Foundation
import Testing
@testable import RadioCore

private func networkS16(_ samples: [Int16]) -> Data {
    Data(samples.flatMap { value -> [UInt8] in let bits = UInt16(bitPattern: value); return [UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8)] })
}
private func networkF32(_ samples: [Float]) -> Data {
    Data(samples.flatMap { value -> [UInt8] in let bits = value.bitPattern; return (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) } })
}

@Test func networkPCMDecodesSigned16AcrossEveryByteBoundary() throws {
    let expected: [Float] = [-1, -0.5, 0, 0.5, Float(32767) / 32768]
    let bytes = networkS16([-32768, -16384, 0, 16384, 32767])
    var parser = try NetworkPCMParser(configuration: .init())
    var output: [Float] = []
    for byte in bytes { output += try parser.append(Data([byte])) }
    try parser.finish()
    #expect(output == expected && parser.bytesReceived == 10 && parser.framesDecoded == 5)
    #expect(parser.pendingByteCount == 0)
    #expect(throws: NetworkPCMError.self) { try parser.append(Data([0, 0])) }
}

@Test func networkPCMPreservesChannelFramingBeforeMixingOrSelection() throws {
    let bytes = networkS16([16384, -16384, 32767, 0, -32768, 16384])
    let configuration = NetworkPCMConfiguration(channels: 2)
    var mix = try NetworkPCMParser(configuration: configuration)
    var right = try NetworkPCMParser(configuration: configuration, channel: .channel(1))
    var mixed: [Float] = [], selected: [Float] = []
    for chunk in [bytes.prefix(3), bytes.dropFirst(3).prefix(4), bytes.dropFirst(7)] {
        mixed += try mix.append(Data(chunk)); selected += try right.append(Data(chunk))
    }
    try mix.finish(); try right.finish()
    #expect(mixed == [0, Float(32767) / 65536, -0.25])
    #expect(selected == [-0.5, 0, 0.5] && mix.framesDecoded == 3)
    #expect(throws: (any Error).self) { try NetworkPCMParser(configuration: configuration, channel: .channel(2)) }
}

@Test func networkPCMFloat32RejectsNonFiniteAndCountsSaturation() throws {
    var parser = try NetworkPCMParser(configuration: .init(format: .float32LittleEndian))
    let bytes = networkF32([-2, -0.25, 0, 0.75, 2])
    var result: [Float] = []
    for byte in bytes { result += try parser.append(Data([byte])) }
    try parser.finish()
    #expect(result == [-1, -0.25, 0, 0.75, 1] && parser.clippedSamples == 2)
    for value: Float in [.nan, .infinity, -.infinity] {
        var invalid = try NetworkPCMParser(configuration: .init(format: .float32LittleEndian))
        #expect(throws: NetworkPCMError.self) { try invalid.append(networkF32([value])) }
        #expect(invalid.framesDecoded == 0)
    }
}

@Test func networkPCMTruncatedFrameAndChunkBoundsFailExplicitly() throws {
    var stereo = try NetworkPCMParser(configuration: .init(channels: 2))
    #expect(try stereo.append(Data([0, 0, 0])).isEmpty)
    #expect(throws: NetworkPCMError.truncatedFrame(1)) { try stereo.finish() }
    var bounded = try NetworkPCMParser(configuration: .init())
    #expect(throws: NetworkPCMError.self) { try bounded.append(Data(repeating: 0, count: NetworkPCMParser.maximumChunkBytes + 1)) }
}

@Test func networkPCMConfigurationAcceptsOnlyExplicitLocalAudioContracts() throws {
    #expect(NetworkPCMConfiguration().isValid)
    #expect(NetworkPCMConfiguration(host: "::1", channels: 2, format: .float32LittleEndian).isValid)
    for host in ["localhost", "0.0.0.0", "192.168.1.2", "example.com", "127.0.0.1.example.com"] {
        #expect(throws: NetworkPCMError.self) { try NetworkPCMConfiguration(host: host).validated() }
    }
    #expect(!NetworkPCMConfiguration(port: 0).isValid)
    #expect(!NetworkPCMConfiguration(sampleRate: .nan).isValid)
    #expect(!NetworkPCMConfiguration(channels: 0).isValid)
    #expect(!NetworkPCMConfiguration(channels: 33).isValid)
}
