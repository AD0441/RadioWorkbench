import Foundation

public enum RadioMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case morse, ft8, ft4, digitalVoice, rtty, psk31, dtmf, bitAnalysis, pocsag, fiveTones
    case wefax, satelliteAPT, sstv, sitorA, navtex, acars, packet, ale, hell, mt63, gmdss, dgps, loran, globeWireless, selectiveTones
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .morse: "Morse / CW"
        case .ft8: "FT8"
        case .ft4: "FT4"
        case .digitalVoice: "Voz digital / DSD"
        case .rtty: "RTTY"
        case .psk31: "PSK31"
        case .dtmf: "DTMF"
        case .bitAnalysis: "Análisis FSK"
        case .pocsag: "POCSAG / pagers"
        case .fiveTones: "Cinco tonos / Selcall"
        case .wefax: "Fax meteorológico"
        case .satelliteAPT: "Satélite / APT"
        case .sstv: "SSTV"
        case .sitorA: "SITOR-A"
        case .navtex: "SITOR-B / NAVTEX"
        case .acars: "ACARS"
        case .packet: "Packet / APRS"
        case .ale: "ALE"
        case .hell: "Hellschreiber"
        case .mt63: "MT63"
        case .gmdss: "GMDSS / DSC"
        case .dgps: "DGPS"
        case .loran: "LORAN-C"
        case .globeWireless: "Globe Wireless"
        case .selectiveTones: "CTCSS / tonos"
        }
    }
    public var isNative: Bool { [.morse, .rtty, .psk31, .dtmf, .bitAnalysis, .sstv, .wefax, .satelliteAPT, .navtex, .packet, .selectiveTones, .hell].contains(self) }
    public var isImage: Bool { [.sstv, .wefax, .satelliteAPT, .hell].contains(self) }
    public var isMultimon: Bool { self == .pocsag || self == .fiveTones }
    public var isAudioAvailable: Bool { isNative || self == .acars || isMultimon || self == .ft8 || self == .ft4 || self == .digitalVoice }
    public var family: String {
        switch self {
        case .morse, .ft8, .ft4, .rtty, .psk31, .dtmf, .bitAnalysis: "Audio · disponible"
        case .wefax, .satelliteAPT, .sstv: "Imágenes"
        case .sitorA, .navtex, .gmdss, .dgps, .loran, .globeWireless: "Marítimo y navegación"
        default: "Otros modos"
        }
    }
    public var symbol: String {
        switch self {
        case .morse: "waveform"
        case .rtty: "text.cursor"
        case .psk31: "waveform.path"
        case .dtmf, .selectiveTones, .fiveTones: "number"
        case .bitAnalysis: "chart.xyaxis.line"
        case .wefax, .satelliteAPT, .sstv: "photo"
        case .acars: "airplane"
        case .navtex, .sitorA, .gmdss: "ferry"
        default: "antenna.radiowaves.left.and.right"
        }
    }
    public var summary: String {
        switch self {
        case .morse: "CW manual o CWKit automático/neuronal (macOS 15+), con tono y velocidad estimados."
        case .ft8, .ft4: "FT8/FT4 desde USB y audio/WAV: LDPC + CRC, ventanas de 15/7,5 s. Recepción sin transmisión."
        case .digitalVoice: "DSD-neo para voz digital desde discriminador NFM; descarga verificada del motor arm64."
        case .rtty: "RTTY ITA2 (5 bits) o ASCII 7/8 bits, sin paridad, con baud/shift y polaridad ajustables."
        case .psk31: "Recepción BPSK31 y Varicode ASCII. Ajusta con precisión la frecuencia de audio."
        case .dtmf: "Detección de las 16 combinaciones de tonos de teclado."
        case .bitAnalysis: "Discriminador FSK para explorar tonos y transiciones; no identifica por sí solo un protocolo."
        case .pocsag: "POCSAG 512/1200/2400 desde discriminador FM: capcode, función y texto, con corrección BCH."
        case .fiveTones: "Secuencias selectivas ZVEI1/2/3, PZVEI, DZVEI, EEA, EIA y CCIR desde audio FM."
        case .wefax: "Recepción de radiofax HF: IOC, LPM, inicio manual e inversión de imagen."
        case .satelliteAPT: "Recepción APT desde audio de FM: envolvente AM 2400 Hz y canales A/B."
        case .sstv: "41 formatos SSTV: clásicos y MMSSTV MP/MR/ML, MP-N/MC-N; VIS clásico, extendido y N-VIS."
        case .navtex: "SITOR-B colectivo: FSK 100 baud, CCIR 476, sincronía de phasing y dos copias con FEC."
        case .sitorA: "SITOR-A: recepción de bloques ARQ y sincronización; sin transmisión automática."
        case .acars: "ACARS VHF desde audio AM: matrícula, vuelo, etiqueta y mensajes validados por acarsdec."
        case .packet: "Packet/APRS AFSK 1200: Bell 202, NRZI, HDLC y tramas AX.25 con CRC verificado."
        case .ale: "ALE: recepción 2G/3G requiere un motor especializado."
        case .hell: "Hellschreiber por pulsos: Feld, Slow y X5/X9. Raster visual continuo y exportación PNG; sin OCR."
        case .mt63: "MT63: recepción multicarrier e interleaving; candidato fldigi."
        case .gmdss: "DSC: sincronización, FEC y mensajes marítimos. Candidato xng sobre I/Q."
        case .dgps: "DGPS: decodificación MSK/RTCM y catálogo de estaciones; integración pendiente."
        case .loran: "LORAN-C usa pulsos RF; una captura de audio corriente no garantiza evidencia suficiente."
        case .globeWireless: "Globe Wireless: no hay todavía un motor abierto verificado para esta implementación."
        case .selectiveTones: "CTCSS: búsqueda automática de 51 tonos subaudio, confianza y duración. Cinco tonos en su apartado; DCS pendiente."
        }
    }
    public var sourceURL: URL? {
        let source: String? = switch self {
        case .wefax, .sstv, .sitorA, .navtex, .hell, .mt63: "https://github.com/w1hkj/fldigi"
        case .morse: "https://github.com/captobie/cwdecode"
        case .ft8, .ft4: "https://github.com/kgoba/ft8_lib"
        case .digitalVoice: "https://github.com/arancormonk/dsd-neo"
        case .acars: "https://github.com/szpajder/libacars"
        case .packet: "https://github.com/wb2osz/direwolf"
        case .gmdss: "https://github.com/airframesio/xng"
        case .satelliteAPT: "https://github.com/SatDump/SatDump"
        case .pocsag, .fiveTones: "https://github.com/EliasOenal/multimon-ng"
        default: nil
        }
        return source.flatMap(URL.init(string:))
    }
}

public enum SSTVNoiseReduction: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "Sin reducción"
    case balanced = "Equilibrada"
    case strong = "Intensa"

    public var id: String { rawValue }
}

public struct DecoderSettings: Codable, Equatable, Sendable {
    public var frequency: Double = 700
    public var wordsPerMinute: Double = 20
    public var baud: Double = 45.45
    public var shift: Double = 170
    public var threshold: Double = 0.08
    public var inverted = false
    public var audioChannel: AudioChannelSelection = .mix
    public var sstvFormat: SSTVFormat = .automatic
    public var sstvColorRange: SSTVColorRange = .bt601
    public var sstvRobot36Compatibility = false
    public var sstvAutoCalibrate = true
    public var sstvNoiseReduction: SSTVNoiseReduction = .balanced
    public var imageAutoSync = true
    public var imageStartSeconds = 0.0
    public var imageClockPPM = 0.0
    public var faxLinesPerMinute = 120.0
    public var faxIOC = 576
    public var pagerRate: PagerRate = .automatic
    public var pagerCorrectionBits = 2
    public var pagerShowEmpty = false
    public var fiveToneStandard: FiveToneStandard = .zvei1
    public var rttyEncoding: RTTYEncoding = .ita2
    public var hellVariant: HellVariant = .feld
    public var cwEngine: CWEngine = .manual
    public var ftxStartSeconds = 0.0
    public var digitalVoiceProtocol: DigitalVoiceProtocol = .dmr
    public init() {}
    public func validated(sampleRate: Double, mode: RadioMode) throws {
        guard sampleRate.isFinite, sampleRate >= 4000, sampleRate <= 384000,
              frequency.isFinite, frequency > 0, frequency + (mode == .navtex ? 85 : mode == .rtty || mode == .bitAnalysis ? shift / 2 : 0) < sampleRate / 2,
              frequency - (mode == .navtex ? 85 : mode == .rtty || mode == .bitAnalysis ? shift / 2 : 0) > 0,
              (mode != .sstv && mode != .wefax) || (frequency + 400 < sampleRate / 2 && frequency - (mode == .sstv ? 800 : 400) > 0),
              wordsPerMinute.isFinite, (5...80).contains(wordsPerMinute),
              baud.isFinite, (20...300).contains(baud), shift.isFinite, (50...1000).contains(shift),
              threshold.isFinite, (0.001...1).contains(threshold),
              imageStartSeconds.isFinite, (0...86400).contains(imageStartSeconds),
              imageClockPPM.isFinite, (-50000...50000).contains(imageClockPPM),
              [60.0,90,120,240].contains(faxLinesPerMinute), [288,576].contains(faxIOC),
              mode != .satelliteAPT || sampleRate >= 11025 else {
            throw RadioError.invalidSettings
        }
        guard ftxStartSeconds.isFinite, (0...86400).contains(ftxStartSeconds) else { throw RadioError.invalidSettings }
        if mode == .digitalVoice && sampleRate < 48000 { throw RadioError.invalidSettings }
        if mode == .packet && (sampleRate < 8000 || frequency - 500 <= 0 || frequency + 500 >= sampleRate / 2) { throw RadioError.invalidSettings }
        if mode == .hell && (frequency - hellVariant.bandwidthHz / 2 <= 0 || frequency + hellVariant.bandwidthHz / 2 >= sampleRate / 2) { throw RadioError.invalidSettings }
        if mode.isMultimon && (sampleRate < 8000 || !(0...2).contains(pagerCorrectionBits)) { throw RadioError.invalidSettings }
    }
    private enum CodingKeys: String, CodingKey {
        case frequency, wordsPerMinute, baud, shift, threshold, inverted, audioChannel, sstvFormat, sstvColorRange,
            sstvRobot36Compatibility, sstvAutoCalibrate, sstvNoiseReduction, imageAutoSync, imageStartSeconds,
            imageClockPPM, faxLinesPerMinute, faxIOC, pagerRate, pagerCorrectionBits, pagerShowEmpty, fiveToneStandard, rttyEncoding, hellVariant, cwEngine, ftxStartSeconds, digitalVoiceProtocol
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try c.decodeIfPresent(Double.self, forKey: .frequency) ?? frequency
        wordsPerMinute = try c.decodeIfPresent(Double.self, forKey: .wordsPerMinute) ?? wordsPerMinute
        baud = try c.decodeIfPresent(Double.self, forKey: .baud) ?? baud
        shift = try c.decodeIfPresent(Double.self, forKey: .shift) ?? shift
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? threshold
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? inverted
        audioChannel = try c.decodeIfPresent(AudioChannelSelection.self, forKey: .audioChannel) ?? audioChannel
        sstvFormat = try c.decodeIfPresent(SSTVFormat.self, forKey: .sstvFormat) ?? sstvFormat
        sstvColorRange = try c.decodeIfPresent(SSTVColorRange.self, forKey: .sstvColorRange) ?? sstvColorRange
        sstvRobot36Compatibility = try c.decodeIfPresent(Bool.self, forKey: .sstvRobot36Compatibility) ?? sstvRobot36Compatibility
        sstvAutoCalibrate = try c.decodeIfPresent(Bool.self, forKey: .sstvAutoCalibrate) ?? sstvAutoCalibrate
        sstvNoiseReduction = try c.decodeIfPresent(SSTVNoiseReduction.self, forKey: .sstvNoiseReduction) ?? sstvNoiseReduction
        imageAutoSync = try c.decodeIfPresent(Bool.self, forKey: .imageAutoSync) ?? imageAutoSync
        imageStartSeconds = try c.decodeIfPresent(Double.self, forKey: .imageStartSeconds) ?? imageStartSeconds
        imageClockPPM = try c.decodeIfPresent(Double.self, forKey: .imageClockPPM) ?? imageClockPPM
        faxLinesPerMinute = try c.decodeIfPresent(Double.self, forKey: .faxLinesPerMinute) ?? faxLinesPerMinute
        faxIOC = try c.decodeIfPresent(Int.self, forKey: .faxIOC) ?? faxIOC
        pagerRate = try c.decodeIfPresent(PagerRate.self, forKey: .pagerRate) ?? pagerRate
        pagerCorrectionBits = try c.decodeIfPresent(Int.self, forKey: .pagerCorrectionBits) ?? pagerCorrectionBits
        pagerShowEmpty = try c.decodeIfPresent(Bool.self, forKey: .pagerShowEmpty) ?? pagerShowEmpty
        fiveToneStandard = try c.decodeIfPresent(FiveToneStandard.self, forKey: .fiveToneStandard) ?? fiveToneStandard
        rttyEncoding = try c.decodeIfPresent(RTTYEncoding.self, forKey: .rttyEncoding) ?? rttyEncoding
        hellVariant = try c.decodeIfPresent(HellVariant.self, forKey: .hellVariant) ?? hellVariant
        cwEngine = try c.decodeIfPresent(CWEngine.self, forKey: .cwEngine) ?? cwEngine
        ftxStartSeconds = try c.decodeIfPresent(Double.self, forKey: .ftxStartSeconds) ?? 0
        digitalVoiceProtocol = try c.decodeIfPresent(DigitalVoiceProtocol.self, forKey: .digitalVoiceProtocol) ?? .dmr
    }
}

public enum RadioError: LocalizedError {
    case invalidSettings, unsupportedMode, invalidAudio, microphoneDenied
    case unavailableAudioChannel(index: Int, available: Int)
    case acarsEngineUnavailable
    case acarsEngineFailed(String)
    case multimonEngineUnavailable, multimonEngineFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "Parámetros fuera de rango o frecuencia por encima del límite de este archivo."
        case .unsupportedMode: "Este modo necesita un motor adicional. Consulta su ficha de integración."
        case .invalidAudio: "No se pudo leer audio PCM válido de este archivo."
        case .microphoneDenied: "Permite el acceso al micrófono en Ajustes del Sistema → Privacidad y seguridad."
        case .unavailableAudioChannel(let index, let available): "El audio tiene \(available) canal(es); elegiste el canal \(index + 1). Selecciona Mezclar o un canal disponible."
        case .acarsEngineUnavailable: "Este paquete no incluye el motor local ACARS. Abre la versión empaquetada de RadioWorkbench."
        case .acarsEngineFailed(let reason): "Error del motor ACARS: \(reason)"
        case .multimonEngineUnavailable: "Este paquete no incluye el motor POCSAG/tonos. Abre la app empaquetada de RadioWorkbench."
        case .multimonEngineFailed(let reason): "Error del motor POCSAG/tonos: \(reason)"
        }
    }
}
