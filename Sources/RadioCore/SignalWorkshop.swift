import Foundation

/// References are existing, identified laboratory recordings. A catalogue entry
/// never implies that another protocol sharing its appearance is supported.
public enum SignalReference: CaseIterable, Sendable, Identifiable, Hashable {
    case cw, rtty, rttyASCII7, rttyASCII8, psk31, dtmf, ctcss, navtex, sitorA, dgps, packet, flex
    case pocsag(PagerRate), fiveTones, ft8, ft4, ale, wefax, apt, acars, m17Data
    case mt63(MT63Variant), hell(HellVariant), dsc(DSCVariant), sstv(SSTVFormat)

    public static let allCases: [SignalReference] = [
        .cw, .rtty, .rttyASCII7, .rttyASCII8, .psk31, .dtmf, .ctcss, .navtex, .sitorA, .dgps, .packet, .flex,
        .pocsag(.bps512), .pocsag(.bps1200), .pocsag(.bps2400), .fiveTones,
        .ft8, .ft4, .ale, .wefax, .apt, .acars, .m17Data
    ] + MT63Variant.allCases.map(Self.mt63) + HellVariant.allCases.map(Self.hell)
      + DSCVariant.allCases.map(Self.dsc) + SSTVFormat.allCases.filter { $0 != .automatic }.map(Self.sstv)

    public var id: String { fileName }
    public var title: String {
        switch self {
        case .cw: "CW · 700 Hz · 20 WPM"
        case .rtty: "RTTY ITA2 · 45,45 baud · 170 Hz"
        case .rttyASCII7: "RTTY ASCII 7 · 75 baud"
        case .rttyASCII8: "RTTY ASCII 8 · 110 baud"
        case .psk31: "BPSK31 · 31,25 baud · 1500 Hz"
        case .dtmf: "DTMF · 16 combinaciones"
        case .ctcss: "CTCSS · subtono de 100 Hz"
        case .navtex: "NAVTEX · SITOR-B · 100 baud"
        case .sitorA: "SITOR-A · 100 baud · ARQ pasivo"
        case .dgps: "DGPS · MSK 100 bit/s · RTCM 2"
        case .flex: "FLEX · 1600 bit/s · 2-FSK"
        case .packet: "Packet / APRS · AFSK 1200"
        case .pocsag(let rate): "POCSAG · \(rate.title)"
        case .fiveTones: "Cinco tonos · ZVEI1"
        case .ft8: "FT8 · trama de 15 s"
        case .ft4: "FT4 · trama de 7,5 s"
        case .ale: "ALE 2G · ocho tonos"
        case .wefax: "WEFAX · 120 LPM · IOC 576"
        case .apt: "APT · laboratorio histórico · 24 líneas"
        case .acars: "ACARS / ADS-C · mensaje sintético"
        case .m17Data: "M17 · paquete de datos, sin voz"
        case .mt63(let variant): "MT63 · \(variant.title)"
        case .hell(let variant): variant.rawValue
        case .dsc(let variant): "DSC · \(variant.title)"
        case .sstv(let format): "SSTV · \(format.rawValue)"
        }
    }
    public var mode: RadioMode {
        switch self {
        case .cw: .morse
        case .rtty, .rttyASCII7, .rttyASCII8: .rtty
        case .psk31: .psk31
        case .dtmf: .dtmf
        case .ctcss: .selectiveTones
        case .navtex: .navtex
        case .sitorA: .sitorA
        case .dgps: .dgps
        case .flex: .flex
        case .packet: .packet
        case .pocsag: .pocsag
        case .fiveTones: .fiveTones
        case .ft8: .ft8
        case .ft4: .ft4
        case .ale: .ale
        case .wefax: .wefax
        case .apt: .satelliteAPT
        case .acars: .acars
        case .m17Data: .digitalVoice
        case .mt63: .mt63
        case .hell: .hell
        case .dsc: .gmdss
        case .sstv: .sstv
        }
    }
    public var fileName: String {
        switch self {
        case .cw: return "morse_8000_mono_clean"
        case .rtty: return "rtty_8000_mono_clean"
        case .rttyASCII7: return "rtty_ascii7_8000_75baud"
        case .rttyASCII8: return "rtty_ascii8_8000_110baud"
        case .psk31: return "bpsk31_8000_mono_clean"
        case .dtmf: return "dtmf_8000_mono_clean"
        case .ctcss: return "ctcss_8000_mono_100hz"
        case .navtex: return "navtex_8000_mono_clean"
        case .sitorA: return "sitora_8000_arq"
        case .dgps: return "dgps_100_8000_mono_clean"
        case .flex: return "flex_22050_mono_alpha"
        case .packet: return "packet_8000_mono_clean"
        case .pocsag(let rate): return "pocsag_\(rate == .bps512 ? 512 : rate == .bps2400 ? 2400 : 1200)_22050_discriminator_clean"
        case .fiveTones: return "selcall_zvei1_22050_12345"
        case .ft8: return "ft8_12000_cq_clean"
        case .ft4: return "ft4_12000_cq_clean"
        case .ale: return "ale2g_8000_synthetic"
        case .wefax: return "wefax_hf120_ioc576_8000_mono_manual"
        case .apt: return "noaa_apt_2400am_48000_mono_24lines"
        case .acars: return "acars_adsc_12000"
        case .m17Data: return "m17_packet_48000_synthetic"
        case .mt63(let variant): return variant.fixtureName
        case .hell(let variant):
            return switch variant {
            case .feld: "hell_feld_8000_cq_clean"
            case .slow14: "hell_slow14_8000_cq_clean"
            case .slowFldigi: "hell_slow_fldigi_8000_cq_clean"
            case .x5: "hell_x5_8000_cq_clean"
            case .x9: "hell_x9_8000_cq_clean"
            }
        case .dsc(let variant): return variant == .vhf ? "dsc_vhf_48000_synthetic" : "dsc_mf_hf_48000_synthetic"
        case .sstv(let format):
            let key = format.rawValue.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
            if format == .robot36 { return "sstv_robot36_8000_mono_clean" }
            if format == .robot72 { return "sstv_robot72_8000_mono_clean" }
            if format == .wraase180 { return "sstv_wraasesc2_180_8000_mono_clean" }
            if ["mp", "mr", "ml", "mc"].contains(where: { key.hasPrefix($0) }) { return "sstv_mmsstv_\(key)_8000_clean" }
            return "sstv_\(key)_8000_mono_clean"
        }
    }
    /// For image protocols this describes an observable outcome, not text OCR.
    public var expectedText: String {
        switch self {
        case .cw, .rtty: "CQ TEST 123"
        case .rttyASCII7: "CQ ASCII7 RADIOWORKBENCH"
        case .rttyASCII8: "CQ ASCII8 RADIOWORKBENCH"
        case .psk31: "CQ test 123"
        case .dtmf: "123A456B789C*0#D"
        case .ctcss: "Tono de 100 Hz entre 0,5 y 5,5 s"
        case .navtex: "ZCZC SA01 · TEST MESSAGE ONLY · NNNN"
        case .sitorA: "TEST SITOR A123 · una retransmisión con respuesta observada"
        case .dgps: "Estación 777 · RWB DGPS TEST 014 · posición de referencia TX sintética"
        case .flex: "Capcode 1234567 · CQ RADIOWORKBENCH FLEX TEST"
        case .packet: "TEST-1>APRS · posición 33°30′ S, 70°40′ W"
        case .pocsag(let rate): "Capcode 123456 · función 3 · CQ RADIOWORKBENCH \(rate == .bps512 ? 512 : rate == .bps2400 ? 2400 : 1200)"
        case .fiveTones: "Secuencia 12345 · ZVEI1"
        case .ft8, .ft4: "Mensaje CQ de laboratorio; CRC verificado por el motor"
        case .ale: "RADIOWORKBENCH TEST"
        case .wefax: "Patrón de imagen de laboratorio · inicio manual en 0,5 s"
        case .apt: "24 líneas con canales A/B y telemetría sintéticos"
        case .acars: "Un mensaje ADS-C de ejemplo libacars"
        case .m17Data: "Paquete M17 sintético; no contiene una conversación DMR ni voz de referencia"
        case .mt63: "Texto de laboratorio tras adquirir sincronismo y entrelazado"
        case .hell: "Raster de CQ; el motor no aplica OCR"
        case .dsc: "Llamada DSC sintética con comprobación ECC; sin transmisión RF"
        case .sstv(let format): "Imagen de patrón y cabecera \(format.rawValue); no es una recepción RF"
        }
    }
    public var explanation: String {
        switch self {
        case .cw: "Un tono que se interrumpe. El punto dura 60 ms a 20 WPM; la raya dura tres puntos. Los espacios también codifican información."
        case .rtty, .rttyASCII7, .rttyASCII8: "Dos tonos de 1415 y 1585 Hz, separados 170 Hz. ITA2 usa cambios de letras/cifras; ASCII usa otra trama. LSB puede invertir la polaridad."
        case .psk31: "Cambios de fase a 31,25 símbolos/s. Una línea estrecha en el espectro no confirma PSK31."
        case .dtmf: "Cada tecla combina un tono de fila y uno de columna. El waterfall permite ver los dos a la vez."
        case .ctcss: "Señal subaudio, no voz. Un pasa-altos de 300 Hz elimina el tono antes de que llegue al detector."
        case .pocsag: "Audio de discriminador FM con transiciones NRZ: no es una referencia de voz ni un par de tonos AFSK. Evita escucharlo con volumen alto."
        case .flex: "FSK multinivel desde discriminador FM plano. La tasa de símbolos y la cantidad de niveles determinan los bit/s; conserva las fases y los límites de fragmento. La muestra es 1600 bit/s, 2-FSK, fase A."
        case .sitorA: "Ráfagas de tres caracteres en 210 ms, separadas por pausas en ciclos de 450 ms. La muestra incluye el retorno de 70 ms y una retransmisión; recibir solo un sentido no confirma entrega ARQ."
        case .dgps: "MSK de fase continua alrededor de 800 Hz. Las palabras RTCM 2 incluyen paridad encadenada; el ejemplo transmite texto y una referencia ECEF ficticios, sin calcular la ubicación del receptor."
        case .wefax: "La frecuencia de audio representa brillo. Con inicio manual se necesita la fase temporal correcta; el dial USB se sitúa normalmente 1,9 kHz por debajo de la portadora."
        case .apt: "Subportadora AM de 2400 Hz obtenida de FM. Muestra histórica y sintética: los NOAA-15/18/19 ya no son objetivos APT activos."
        case .m17Data: "Ejemplo de trama de datos M17. Seleccionarlo aquí permite estudiar esa trama; no cambia DMR en silencio ni sirve como prueba de voz DMR."
        case .sstv(let format): format.isNarrow ? "SSTV de banda estrecha con N-VIS. El contenido de imagen está en 2044–2300 Hz; conserva también la cabecera y sincronía." : "La cabecera identifica el formato; después el tono cambia con los colores y las líneas. El taller muestra los primeros 12 s, no toda la imagen."
        default: mode.receptionProfile(settings: settings).note
        }
    }
    public var provenance: String {
        switch self {
        case .acars: "Modulación sintética propia; mensaje de ejemplo libacars (MIT). Fuentes y avisos incluidos en la app."
        case .mt63: "WAV de laboratorio generado con el transmisor de referencia fldigi; fuentes y licencia incluidas en la app."
        case .sstv(let format) where format.rawValue.hasPrefix("M"):
            "Fixture de laboratorio identificado en los manifiestos SSTV/MMSSTV del proyecto; no procede de los medios de Artemis."
        default: "WAV de laboratorio del proyecto, identificado en sus manifiestos y pruebas; no es una captura de radio ni un medio copiado de Artemis."
        }
    }
    public var analysisFrequencyLimit: Double { self == .ctcss ? 400 : self == .apt ? 6000 : 4000 }
    public var settings: DecoderSettings {
        var value = DecoderSettings()
        value.frequency = mode.receptionProfile.center
        value.wordsPerMinute = 20; value.baud = 45.45; value.shift = 170
        switch self {
        case .rttyASCII7: value.rttyEncoding = .ascii7; value.baud = 75
        case .rttyASCII8: value.rttyEncoding = .ascii8; value.baud = 110
        case .ctcss: value.threshold = 0.02
        case .pocsag(let rate): value.pagerRate = rate
        case .dgps: value.dgpsRate = .bps100
        case .mt63(let variant): value.mt63Variant = variant; value.frequency = 1500
        case .hell(let variant): value.hellVariant = variant; value.frequency = variant == .x9 ? 2000 : 1500; value.threshold = 0.04; value.imageStartSeconds = 0.2
        case .dsc(let variant): value.dscVariant = variant; value.frequency = 1700
        case .sstv(let format): value.sstvFormat = format; value.frequency = 1900
        case .wefax: value.imageStartSeconds = 0.5
        case .m17Data: value.digitalVoiceProtocol = .m17
        default: break
        }
        return value
    }
    public static func matching(mode: RadioMode, settings: DecoderSettings) -> SignalReference? {
        switch mode {
        case .rtty: settings.rttyEncoding == .ascii7 ? .rttyASCII7 : settings.rttyEncoding == .ascii8 ? .rttyASCII8 : .rtty
        case .bitAnalysis: .rtty
        case .fiveTones: settings.fiveToneStandard == .zvei1 ? .fiveTones : nil
        case .pocsag: .pocsag(settings.pagerRate == .automatic ? .bps1200 : settings.pagerRate)
        case .mt63: .mt63(settings.mt63Variant)
        case .hell: .hell(settings.hellVariant)
        case .gmdss: .dsc(settings.dscVariant)
        case .sstv: .sstv(settings.sstvFormat == .automatic ? .martinM1 : settings.sstvFormat)
        case .digitalVoice: settings.digitalVoiceProtocol == .m17 ? .m17Data : nil
        default: allCases.first { $0.mode == mode }
        }
    }
}

public struct SignalProbeResult: Sendable {
    public let bins: [Float]
    /// Time increases downwards. Every row has the same frequency axis as bins.
    public let waterfall: [[Float]]
    public let rowTimes: [Double]
    public let upperFrequency: Double
    public let sampleRate: Double
    public let channels: Int
    public let secondsAnalyzed: Double
    public let levelDB: Double
    public let clippedSamples: Int
}

public enum SignalProbe {
    public static let maximumSeconds = 12.0
    public static let maximumRows = 96
    public static let frequencyBins = 256

    /// Bounded, contiguous 2048-sample FFT windows over the first twelve seconds.
    /// Power is averaged in linear units, both over time and when reducing bins.
    /// This is an audio comparison, not RF power, SNR or protocol classification.
    public static func analyze(url: URL, channel: AudioChannelSelection = .mix, frequencyLimit: Double = 4000) throws -> SignalProbeResult {
        guard frequencyLimit.isFinite, frequencyLimit > 0 else { throw RadioError.invalidSettings }
        let reader = try AudioFileReader(url: url, channel: channel), analyzer = SpectrumAnalyzer()
        let maximum = Int(reader.sampleRate * maximumSeconds)
        let duration = min(maximumSeconds, reader.duration)
        let upper = min(6000, frequencyLimit, reader.sampleRate / 2)
        let binWidth = reader.sampleRate / 2048
        let sourceBinCount = max(1, Int(upper / binWidth))
        let actualUpper = Double(sourceBinCount) * binWidth
        let rowCount = min(maximumRows, max(1, Int(ceil(duration * reader.sampleRate / 2048))))
        var rows = [[Double]](repeating: [Double](repeating: 0, count: frequencyBins), count: rowCount)
        var rowSamples = [Int](repeating: 0, count: rowCount)
        var average = [Double](repeating: 0, count: frequencyBins)
        var window: [Float] = []; window.reserveCapacity(2048)
        var samplesRead = 0, totalWindows = 0, sumSquares = 0.0, clipped = 0

        func consumeWindow() throws {
            try Task.checkCancellation()
            let frame = analyzer.analyze(window, sampleRate: reader.sampleRate)
            var reduced = [Double](repeating: 0, count: frequencyBins)
            var counts = [Int](repeating: 0, count: frequencyBins)
            for source in 0..<min(sourceBinCount, frame.bins.count) {
                let target = min(frequencyBins - 1, source * frequencyBins / sourceBinCount)
                reduced[target] += pow(10, Double(frame.bins[source]) / 10); counts[target] += 1
            }
            // Interpolate only to display below the native FFT resolution.
            for target in 0..<frequencyBins {
                if counts[target] > 0 { reduced[target] /= Double(counts[target]) }
                else {
                    let source = min(frame.bins.count - 1, target * sourceBinCount / frequencyBins)
                    reduced[target] = pow(10, Double(frame.bins[source]) / 10)
                }
            }
            let start = max(0, samplesRead - window.count)
            let row = min(rowCount - 1, Int(Double(start) / reader.sampleRate / max(duration, 0.0001) * Double(rowCount)))
            for target in 0..<frequencyBins { rows[row][target] += reduced[target]; average[target] += reduced[target] }
            rowSamples[row] += 1; totalWindows += 1; window.removeAll(keepingCapacity: true)
        }
        while samplesRead < maximum, let chunk = try reader.next() {
            try Task.checkCancellation()
            for sample in chunk.prefix(maximum - samplesRead) {
                sumSquares += Double(sample) * Double(sample)
                if abs(sample) >= 0.999 { clipped += 1 }
                window.append(sample); samplesRead += 1
                if window.count == 2048 { try consumeWindow() }
            }
        }
        if !window.isEmpty { try consumeWindow() }
        guard totalWindows > 0, samplesRead > 0 else { throw RadioError.invalidAudio }
        let usedRows = rowSamples.indices.filter { rowSamples[$0] > 0 }
        return .init(bins: average.map { Float(10 * log10(max(1e-10, $0 / Double(totalWindows)))) },
                     waterfall: usedRows.map { row in rows[row].map { Float(10 * log10(max(1e-10, $0 / Double(rowSamples[row])))) } },
                     rowTimes: usedRows.map { Double($0) * duration / Double(rowCount) },
                     upperFrequency: actualUpper, sampleRate: reader.sampleRate, channels: reader.channelCount,
                     secondsAnalyzed: Double(samplesRead) / reader.sampleRate,
                     levelDB: 10 * log10(max(1e-10, sumSquares / Double(samplesRead))), clippedSamples: clipped)
    }
}
