import Foundation

public final class DecoderEngine {
    private var cw: MorseDecoder?
    private var rtty: RTTYDecoder?
    private var psk: PSK31Decoder?
    private var dtmf: DTMFDecoder?
    private var sitorB: SITORBDecoder?
    private var packet: PacketAFSK1200Decoder?
    private var selective: SelectiveToneDecoder?
    private var hell: HellDecoder?
    private var imageDecoder: ImageDecoder?
    private let mode: RadioMode
    public init(mode: RadioMode, sampleRate: Double, settings: DecoderSettings) throws {
        guard mode.isNative else { throw RadioError.unsupportedMode }
        try settings.validated(sampleRate: sampleRate, mode: mode)
        self.mode = mode
        switch mode {
        case .morse: cw = MorseDecoder(sampleRate: sampleRate, settings: settings)
        case .rtty, .bitAnalysis: rtty = RTTYDecoder(sampleRate: sampleRate, settings: settings)
        case .psk31: psk = PSK31Decoder(sampleRate: sampleRate, settings: settings)
        case .dtmf: dtmf = DTMFDecoder(sampleRate: sampleRate, settings: settings)
        case .navtex: sitorB = SITORBDecoder(sampleRate: sampleRate, settings: settings)
        case .packet: packet = PacketAFSK1200Decoder(sampleRate: sampleRate, settings: settings)
        case .selectiveTones: selective = SelectiveToneDecoder(sampleRate: sampleRate, settings: settings)
        case .hell: hell = HellDecoder(sampleRate: sampleRate, settings: settings)
        case .sstv, .wefax, .satelliteAPT: imageDecoder = ImageDecoder(mode: mode, sampleRate: sampleRate, settings: settings)
        default: break
        }
    }
    public func process(_ samples: [Float]) {
        imageDecoder?.process(samples)
        sitorB?.process(samples)
        packet?.process(samples)
        selective?.process(samples)
        hell?.process(samples)
        // Switch once per block; avoid existential dispatch and optional COW per sample.
        if var decoder = cw { for sample in samples { decoder.push(sample) }; cw = decoder }
        if var decoder = rtty { for sample in samples { decoder.push(sample) }; rtty = decoder }
        if var decoder = psk { for sample in samples { decoder.push(sample) }; psk = decoder }
        if var decoder = dtmf { for sample in samples { decoder.push(sample) }; dtmf = decoder }
    }
    public func finish() { cw?.finish(); imageDecoder?.finish(); hell?.finish() }
    public var image: RadioImage? { imageDecoder?.image ?? hell?.image }
    public var packetReceptions: [PacketReception] { packet?.receptions ?? [] }
    public var sstvCalibration: SSTVCalibration? { imageDecoder?.calibration }
    public var status: String { sitorB?.status ?? packet?.status ?? selective?.status ?? hell?.status ?? "" }
    public var text: String {
        if mode == .bitAnalysis, let rtty {
            return "Tonos de FSK\nMark: \(Int(rtty.markLevel * 100)) %\nSpace: \(Int(rtty.spaceLevel * 100)) %\nTransiciones observadas: \(rtty.transitions)\n\nLa tasa y el protocolo requieren confirmación independiente."
        }
        return cw?.text ?? rtty?.text ?? psk?.text ?? dtmf?.text ?? sitorB?.text ?? packet?.text ?? selective?.text ?? imageDecoder?.status ?? hell?.status ?? ""
    }
}
