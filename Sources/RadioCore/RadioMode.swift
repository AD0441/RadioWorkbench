import Foundation

public enum RadioMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case morse, rtty, psk31, dtmf, bitAnalysis
    case wefax, satelliteAPT, sstv, sitorA, navtex, acars, packet, ale, hell, mt63, gmdss, dgps, loran, globeWireless, selectiveTones
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .morse: "Morse / CW"
        case .rtty: "RTTY"
        case .psk31: "PSK31"
        case .dtmf: "DTMF"
        case .bitAnalysis: "Análisis FSK"
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
    public var isNative: Bool { [.morse, .rtty, .psk31, .dtmf, .bitAnalysis, .sstv, .wefax, .satelliteAPT, .navtex, .packet, .selectiveTones].contains(self) }
    public var isImage: Bool { [.sstv, .wefax, .satelliteAPT].contains(self) }
    public var isAudioAvailable: Bool { isNative || self == .acars }
    public var family: String {
        switch self {
        case .morse, .rtty, .psk31, .dtmf, .bitAnalysis: "Audio · disponible"
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
        case .dtmf, .selectiveTones: "number"
        case .bitAnalysis: "chart.xyaxis.line"
        case .wefax, .satelliteAPT, .sstv: "photo"
        case .acars: "airplane"
        case .navtex, .sitorA, .gmdss: "ferry"
        default: "antenna.radiowaves.left.and.right"
        }
    }
    public var summary: String {
        switch self {
        case .morse: "Recepción CW con frecuencia, velocidad y umbral ajustables."
        case .rtty: "Recepción ITA2 (Baudot): 5 bits, LTRS/FIGS y polaridad invertida."
        case .psk31: "Recepción BPSK31 y Varicode ASCII. Ajusta con precisión la frecuencia de audio."
        case .dtmf: "Detección de las 16 combinaciones de tonos de teclado."
        case .bitAnalysis: "Discriminador FSK para explorar tonos y transiciones; no identifica por sí solo un protocolo."
        case .wefax: "Recepción de radiofax HF: IOC, LPM, inicio manual e inversión de imagen."
        case .satelliteAPT: "Recepción APT desde audio de FM: envolvente AM 2400 Hz y canales A/B."
        case .sstv: "41 formatos SSTV: clásicos y MMSSTV MP/MR/ML, MP-N/MC-N; VIS clásico, extendido y N-VIS."
        case .navtex: "SITOR-B colectivo: FSK 100 baud, CCIR 476, sincronía de phasing y dos copias con FEC."
        case .sitorA: "SITOR-A: recepción de bloques ARQ y sincronización; sin transmisión automática."
        case .acars: "ACARS VHF desde audio AM: matrícula, vuelo, etiqueta y mensajes validados por acarsdec."
        case .packet: "Packet/APRS AFSK 1200: Bell 202, NRZI, HDLC y tramas AX.25 con CRC verificado."
        case .ale: "ALE: recepción 2G/3G requiere un motor especializado."
        case .hell: "Hellschreiber: raster de caracteres, candidatos fldigi."
        case .mt63: "MT63: recepción multicarrier e interleaving; candidato fldigi."
        case .gmdss: "DSC: sincronización, FEC y mensajes marítimos. Candidato xng sobre I/Q."
        case .dgps: "DGPS: decodificación MSK/RTCM y catálogo de estaciones; integración pendiente."
        case .loran: "LORAN-C usa pulsos RF; una captura de audio corriente no garantiza evidencia suficiente."
        case .globeWireless: "Globe Wireless: no hay todavía un motor abierto verificado para esta implementación."
        case .selectiveTones: "CTCSS: búsqueda automática de 51 tonos subaudio, confianza y duración. DCS y cinco tonos pendientes."
        }
    }
    public var sourceURL: URL? {
        let source: String? = switch self {
        case .wefax, .sstv, .sitorA, .navtex, .hell, .mt63: "https://github.com/w1hkj/fldigi"
        case .acars: "https://github.com/f00b4r0/acarsdec"
        case .packet: "https://github.com/wb2osz/direwolf"
        case .gmdss: "https://github.com/airframesio/xng"
        case .satelliteAPT: "https://github.com/SatDump/SatDump"
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
        if mode == .packet && (sampleRate < 8000 || frequency - 500 <= 0 || frequency + 500 >= sampleRate / 2) { throw RadioError.invalidSettings }
    }
}

public enum RadioError: LocalizedError {
    case invalidSettings, unsupportedMode, invalidAudio, microphoneDenied
    case unavailableAudioChannel(index: Int, available: Int)
    case acarsEngineUnavailable
    case acarsEngineFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "Parámetros fuera de rango o frecuencia por encima del límite de este archivo."
        case .unsupportedMode: "Este modo necesita un motor adicional. Consulta su ficha de integración."
        case .invalidAudio: "No se pudo leer audio PCM válido de este archivo."
        case .microphoneDenied: "Permite el acceso al micrófono en Ajustes del Sistema → Privacidad y seguridad."
        case .unavailableAudioChannel(let index, let available): "El audio tiene \(available) canal(es); elegiste el canal \(index + 1). Selecciona Mezclar o un canal disponible."
        case .acarsEngineUnavailable: "Este paquete no incluye el motor local ACARS. Abre la versión empaquetada de RadioWorkbench."
        case .acarsEngineFailed(let reason): "Error del motor ACARS: \(reason)"
        }
    }
}
