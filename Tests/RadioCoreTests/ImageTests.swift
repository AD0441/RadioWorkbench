import Foundation
import AppKit
import Testing
@testable import RadioCore

private func decodeImageFixture(_ name: String, mode: RadioMode, start: Double = 0, colorRange: SSTVColorRange = .bt601, format: SSTVFormat = .automatic, autoSync: Bool = true) throws -> RadioImage {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
    let reader = try AudioFileReader(url: url)
    var settings = DecoderSettings(); settings.frequency = mode == .satelliteAPT ? 2400 : 1900
    settings.imageStartSeconds = start
    settings.sstvColorRange = colorRange
    settings.sstvFormat = format; settings.imageAutoSync = autoSync
    let decoder = try DecoderEngine(mode: mode, sampleRate: reader.sampleRate, settings: settings)
    while let samples = try reader.next() { decoder.process(samples) }
    decoder.finish()
    let image = try #require(decoder.image, "\(name): \(decoder.text)")
    // Durable reconstructions for visual inspection; synthetic input only.
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("radioworkbench-decoded-images")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let provider = try #require(CGDataProvider(data: Data(image.rgb) as CFData))
    let cgImage = try #require(CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 24,
                                      bytesPerRow: image.width * 3, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let png = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
    try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    return image
}

private struct MMSSTVManifest: Decodable {
    struct Fixture: Decodable {
        struct Specification: Decodable {
            let mode: String; let width: Int; let height: Int; let color_range: String
            let manual: Bool; let bad_header: Bool; let payload_start_seconds: Double
            let expected_error: String?
        }
        let file: String; let specification: Specification
        enum CodingKeys: String, CodingKey { case file; case specification = "protocol" }
    }
    let fixtures: [Fixture]
}

@Test(arguments: [
    "mp73","mp115","mp140","mp175","mr73","mr90","mr115","mr140","mr175",
    "ml180","ml240","ml280","ml320","mp73_n","mp110_n","mp140_n","mc110_n","mc140_n","mc180_n"
].map { "sstv_mmsstv_\($0)_8000_clean" } + [
    "sstv_mmsstv_mp73_8000_fullrange", "sstv_mmsstv_mr73_8000_fullrange", "sstv_mmsstv_mp73_n_8000_fullrange",
    "sstv_mmsstv_mp73_8000_badheader", "sstv_mmsstv_mc110_n_8000_badheader", "sstv_mmsstv_mp73_n_8000_manual",
    "sstv_classic_vis2_8000_unsupported", "sstv_classic_m1_8000_badparity"
])
func mmsstvPublishedModes(_ name: String) throws {
    let url = try #require(Bundle.module.url(forResource: "mmsstv-manifest", withExtension: "json", subdirectory: "Fixtures"))
    let manifest = try JSONDecoder().decode(MMSSTVManifest.self, from: Data(contentsOf: url))
    let specification = try #require(manifest.fixtures.first { $0.file == name + ".wav" }).specification
    if specification.bad_header {
        let audio = try #require(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures"))
        let reader = try AudioFileReader(url: audio)
        var settings = DecoderSettings(); settings.frequency = 1900
        let decoder = try DecoderEngine(mode: .sstv, sampleRate: reader.sampleRate, settings: settings)
        while let samples = try reader.next() { decoder.process(samples) }
        decoder.finish(); #expect(decoder.image == nil)
        if let expected = specification.expected_error { #expect(decoder.text.contains(expected)) }
        return
    }
    let format = try #require(SSTVFormat(rawValue: specification.mode))
    let image = try decodeImageFixture(name, mode: .sstv, start: specification.manual ? specification.payload_start_seconds : 0,
                                      colorRange: specification.color_range == "full" ? .full : .bt601,
                                      format: specification.manual ? format : .automatic, autoSync: !specification.manual)
    #expect(image.width == specification.width); #expect(image.height == specification.height)
    let bars = [[255,255,255],[255,255,0],[0,255,255],[0,255,0],[255,0,255],[255,0,0],[0,0,255],[0,0,0]]
    let gray = [0,36,73,109,146,182,219,255]
    for row in [4,image.height/2,image.height-8] {
        for bar in 0..<8 {
            let column = bar*image.width/8+image.width/16
            for channel in 0..<3 {
                let expected = row<16 ? gray[bar] : bars[row>=image.height-16 ? 7-bar : bar][channel]
                let value = Int(image.rgb[(row*image.width+column)*3+channel])
                #expect(abs(value-expected)<8, "\(name): row \(row), bar \(bar), channel \(channel), value \(value)")
            }
        }
    }
}

@Test func imageAudioMustPreserveVideoAndHeaderBand() throws {
    var settings = DecoderSettings(); settings.frequency = 1900
    for mode in [RadioMode.sstv, .wefax] {
        #expect(throws: RadioError.self) { try DecoderEngine(mode: mode, sampleRate: 4000, settings: settings) }
        #expect(throws: RadioError.self) { try DecoderEngine(mode: mode, sampleRate: 4500, settings: settings) }
        _ = try DecoderEngine(mode: mode, sampleRate: 8000, settings: settings)
    }
}

@Test(arguments: ["sstv_martin_m1_8000_mono_clean", "sstv_martin_m1_8000_mono_offset", "sstv_scottie_s1_8000_mono_clean", "sstv_scottie_s1_8000_mono_offset", "sstv_pd50_8000_mono_clean", "sstv_pd50_8000_mono_offset", "sstv_robot36_8000_mono_clean", "sstv_robot36_8000_mono_offset"])
func independentSSTV(_ name: String) throws {
    let image = try decodeImageFixture(name, mode: .sstv)
    #expect(image.width == 320); #expect(image.height == (name.contains("robot36") ? 240 : 256))
    let bars = [[255,255,255],[255,255,0],[0,255,255],[0,255,0],[255,0,255],[255,0,0],[0,0,255],[0,0,0]]
    for i in 0..<8 {
        for channel in 0..<3 {
            let value = Int(image.rgb[(80 * 320 + i * 40 + 20) * 3 + channel])
            #expect(abs(value - bars[i][channel]) < 8, "\(name): bar \(i), channel \(channel), value \(value)")
        }
    }
}

private struct SSTVFamilyManifest: Decodable {
    struct Fixture: Decodable {
        struct Specification: Decodable { let width: Int; let height: Int; let color_range: String }
        let file: String
        let specification: Specification
        enum CodingKeys: String, CodingKey { case file; case specification = "protocol" }
    }
    let fixtures: [Fixture]
}

@Test(arguments: [
    "sstv_martin_m2_8000_mono_clean", "sstv_martin_m3_8000_mono_clean", "sstv_martin_m4_8000_mono_clean",
    "sstv_scottie_s2_8000_mono_clean", "sstv_scottie_s3_8000_mono_clean", "sstv_scottie_s4_8000_mono_clean", "sstv_scottie_dx_8000_mono_clean",
    "sstv_pd90_8000_mono_clean", "sstv_pd120_8000_mono_clean", "sstv_pd160_8000_mono_clean", "sstv_pd180_8000_mono_clean", "sstv_pd240_8000_mono_clean", "sstv_pd290_8000_mono_clean",
    "sstv_robot72_8000_mono_clean", "sstv_pasokon_p3_8000_mono_clean", "sstv_pasokon_p5_8000_mono_clean", "sstv_pasokon_p7_8000_mono_clean", "sstv_wraasesc2_180_8000_mono_clean",
    "sstv_pd50_8000_mono_fullrange", "sstv_robot36_8000_mono_fullrange"
])
func publishedSSTVFamilyFixture(_ name: String) throws {
    let manifestURL = try #require(Bundle.module.url(forResource: "family-image-manifest", withExtension: "json", subdirectory: "Fixtures"))
    let manifest = try JSONDecoder().decode(SSTVFamilyManifest.self, from: Data(contentsOf: manifestURL))
    let specification = try #require(manifest.fixtures.first { $0.file == name + ".wav" }).specification
    let image = try decodeImageFixture(name, mode: .sstv, colorRange: specification.color_range == "full" ? .full : .bt601)
    #expect(image.width == specification.width); #expect(image.height == specification.height)
    let bars = [[255,255,255],[255,255,0],[0,255,255],[0,255,0],[255,0,255],[255,0,0],[0,0,255],[0,0,0]]
    let gray = [0,36,73,109,146,182,219,255]
    // Check luminance, color ordering and final rows: a wrong line period drifts
    // relative to the sixteen-row patches at the end of a full transmission.
    for row in [4, image.height / 2, image.height - 8] {
        for bar in 0..<8 {
            let column = bar * image.width / 8 + image.width / 16
            for channel in 0..<3 {
                let expected = row < 16 ? gray[bar] : bars[row >= image.height - 16 ? 7-bar : bar][channel]
                let value = Int(image.rgb[(row * image.width + column) * 3 + channel])
                #expect(abs(value - expected) < 8, "\(name): row \(row), bar \(bar), channel \(channel), value \(value)")
            }
        }
    }
}

@Test func independentWEFAX() throws {
    let image = try decodeImageFixture("wefax_hf120_ioc576_8000_mono_manual", mode: .wefax, start: 0.5)
    #expect(image.width == 1810); #expect(image.height == 64)
    for i in 0..<8 {
        let value = Int(image.rgb[(16 * image.width + i * image.width / 8 + image.width / 16) * 3])
        #expect(abs(value - Int((Double(i) / 7 * 255).rounded())) < 25)
        let reversed = Int(image.rgb[(60 * image.width + i * image.width / 8 + image.width / 16) * 3])
        #expect(abs(reversed - Int((Double(7-i) / 7 * 255).rounded())) < 25)
    }
}

@Test(arguments: ["noaa_apt_2400am_16640_mono_24lines", "noaa_apt_2400am_48000_mono_24lines"])
func independentAPT(_ name: String) throws {
    let image = try decodeImageFixture(name, mode: .satelliteAPT)
    #expect(image.width == 1818); #expect(image.height == 24)
    for i in 0..<8 {
        let column = i * 909 / 8 + 909 / 16
        let a = Int(image.rgb[(8 * image.width + column) * 3])
        let b = Int(image.rgb[(8 * image.width + 909 + column) * 3])
        #expect(abs(a - Int((Double(i) / 7 * 255).rounded())) < 35, "\(name): A bar \(i), value \(a)")
        #expect(abs(b - Int((Double(7-i) / 7 * 255).rounded())) < 35, "\(name): B bar \(i), value \(b)")
    }
}
