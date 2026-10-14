import Foundation
import Testing
import AudioRing
@testable import RadioCore

// Published NAUTICAL interleave from Paul Lutus's JNX description; the values
// are wire protocol facts. No encoder calls or receiver tables form this vector.
private let nautical: [UInt8] = [0x66,0x0F,0x66,0x0F,0x59,0x0F,0x47,0x0F,0x4E,0x59,0x74,0x47,0x4D,0x4E,0x1D,0x74,0x47,0x4D,0x65,0x1D,0,0x47,0,0x65]

@Test(arguments: ["clean", "first_bad", "second_bad", "both_bad", "disagree"])
func publishedCCIR476Interleave(_ variant: String) {
    var symbols = nautical
    if variant == "first_bad" || variant == "both_bad" { symbols[4] ^= 1 }
    if variant == "second_bad" || variant == "both_bad" { symbols[9] ^= 1 }
    if variant == "disagree" { symbols[9] = 0x47 }
    let decoder = CCIR476Receiver()
    for bit in [true,false,true,true,false] { decoder.push(bit: bit) }
    for code in symbols {
        for bit in 0..<7 { decoder.push(bit: code & (1 << bit) != 0) }
    }
    #expect(decoder.text == (variant == "both_bad" || variant == "disagree" ? "�AUTICAL" : "NAUTICAL"))
    #expect(decoder.corrected == (variant == "first_bad" || variant == "second_bad" ? 1 : 0))
    #expect(decoder.erased == (variant == "both_bad" || variant == "disagree" ? 1 : 0))
    #expect(decoder.disagreements == (variant == "disagree" ? 1 : 0))
}

private struct NavtexManifest: Decodable {
    struct Fixture: Decodable {
        struct Specification: Decodable {
            let expected_text: String; let inverted: Bool
            let corrected_characters: Int; let erased_characters: Int; let disagreement_characters: Int
        }
        let file: String
        let specification: Specification
        enum CodingKeys: String, CodingKey { case file; case specification = "protocol" }
    }
    let fixtures: [Fixture]
}

private func navtexFixture(_ name: String, channel: AudioChannelSelection = .mix) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    let manifestURL = try #require(Bundle.module.url(forResource: "navtex-manifest", withExtension: "json", subdirectory: "Fixtures"))
    let manifest = try JSONDecoder().decode(NavtexManifest.self, from: Data(contentsOf: manifestURL))
    let specification = try #require(manifest.fixtures.first { $0.file == name + ".wav" }).specification
    let reader = try AudioFileReader(url: url, channel: channel)
    var settings = DecoderSettings(); settings.frequency = 1700; settings.inverted = specification.inverted
    let decoder = try DecoderEngine(mode: .navtex, sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() {
        for offset in stride(from: 0, to: samples.count, by: 317) {
            decoder.process(Array(samples[offset..<min(offset+317,samples.count)]))
        }
    }
    decoder.finish()
    #expect(decoder.text.trimmingCharacters(in: .whitespacesAndNewlines) == (channel == .mix && name.contains("opposite") ? "" : specification.expected_text.trimmingCharacters(in: .whitespacesAndNewlines)))
    if !name.contains("noisy") {
        #expect(decoder.status.contains("FEC: \(specification.corrected_characters) recuperados"))
        #expect(decoder.status.contains("\(specification.erased_characters) ilegibles"))
        #expect(decoder.status.contains("\(specification.disagreement_characters) discrepancias"))
    }
    return decoder.text
}

@Test(arguments: ["clean","offset","noisy","repaired","lost","disagree","inverted","drift","resync"].map { "navtex_8000_mono_\($0)" } + ["navtex_44100_stereo_clean"])
func navtexAudioFixture(_ name: String) throws { _ = try navtexFixture(name) }

@Test(arguments: [AudioChannelSelection.mix, .channel(0), .channel(1)])
func stereoSelectionPreservesOppositePhaseAudio(_ channel: AudioChannelSelection) throws {
    _ = try navtexFixture("navtex_48000_stereo_opposite", channel: channel)
}

@Test func absentChannelIsAnExplicitError() throws {
    let url = try #require(Bundle.module.url(forResource: "navtex_8000_mono_clean", withExtension: "wav", subdirectory: "Fixtures"))
    #expect(throws: RadioError.self) { try AudioFileReader(url: url, channel: .channel(1)) }
    #expect(throws: RadioError.self) { try AudioChannelSelection.channel(-1).validate(channelCount: 2) }
}

@Test func multiChannelRingMixAndSingleChannel() throws {
    let ring = try #require(radio_ring_create(8)); defer { radio_ring_destroy(ring) }
    let left: [Float] = [1,2,3], right: [Float] = [-1,-2,-3], third: [Float] = [3,6,9]
    var output = [Float](repeating: 0, count: 3)
    left.withUnsafeBufferPointer { l in
        right.withUnsafeBufferPointer { r in
            third.withUnsafeBufferPointer { t in
                let channels = [l.baseAddress,r.baseAddress,t.baseAddress]
                #expect(channels.withUnsafeBufferPointer { radio_ring_write(ring, $0.baseAddress, 3, 3) } == 3)
            }
        }
    }
    #expect(output.withUnsafeMutableBufferPointer { radio_ring_read(ring, $0.baseAddress, 3) } == 3)
    #expect(output == [1,2,3])
    right.withUnsafeBufferPointer { r in #expect(radio_ring_write_mono(ring, r.baseAddress, nil, 3) == 3) }
    #expect(output.withUnsafeMutableBufferPointer { radio_ring_read(ring, $0.baseAddress, 3) } == 3)
    #expect(output == right)
}
