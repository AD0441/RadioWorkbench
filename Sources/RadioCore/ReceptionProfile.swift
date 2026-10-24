import Foundation

public enum RFModulation: String, CaseIterable, Identifiable, Codable, Sendable {
    case am = "AM", fm = "FM / NFM", usb = "USB", lsb = "LSB", cw = "CW", iq = "I/Q directo"
    public var id: String { rawValue }
}

public struct ReceptionProfile: Sendable {
    public let modulation: RFModulation
    public let rfBandwidth: Double
    public let audioBand: String
    public let center: Double
    public let note: String
    public init(modulation: RFModulation, rfBandwidth: Double, audioBand: String, center: Double, note: String) {
        self.modulation = modulation; self.rfBandwidth = rfBandwidth
        self.audioBand = audioBand; self.center = center; self.note = note
    }
}

public enum ReceptionBandVariant: String, CaseIterable, Identifiable, Sendable {
    case standard = "Perfil habitual", hf = "HF · banda lateral", vhf = "VHF/UHF · FM"
    public var id: String { rawValue }
}

public extension RadioMode {
    /// A single setup catalogue shared by the inspector and decoder views. RF
    /// filters are starting points, distinct from occupied signal bandwidth.
    func receptionProfile(settings: DecoderSettings, variant: ReceptionBandVariant = .standard) -> ReceptionProfile {
        if self == .digitalVoice { return settings.digitalVoiceProtocol.receptionPreset.profile }
        if self == .gmdss, settings.dscVariant == .vhf {
            return .init(modulation: .fm, rfBandwidth: 16000, audioBand: "1300/2100 Hz · 1200 baud · mono 48 kHz al motor", center: 1700,
                         note: "DSC VHF: NFM y filtro RF inicial de 16 kHz. Deja squelch y reducción de ruido desactivados; conserva toda la ráfaga. No transmite llamadas de socorro.")
        }
        if self == .sstv {
            let narrow = settings.sstvFormat.isNarrow
            return .init(modulation: variant == .vhf ? .fm : .usb, rfBandwidth: variant == .vhf ? 12500 : narrow ? 2800 : 3000,
                         audioBand: narrow ? "Cabecera N-VIS y sincronía; imagen 2044–2300 Hz" : "1100–2300 Hz; conservar VIS y sincronía", center: 1900,
                         note: variant == .vhf ? "SSTV sobre FM: filtro RF inicial de 12,5 kHz, ampliable a 25 kHz según desviación. La FM de los tonos de imagen es distinta de la demodulación RF del receptor." : "SSTV HF: USB. El filtro práctico debe conservar la cabecera y los tonos, además del ancho ocupado por la imagen. Sin squelch ni procesado de voz.")
        }
        if self == .hell {
            let requested = settings.frequency.isFinite && (1...192000).contains(settings.frequency) ? settings.frequency : 1500
            let center = max(requested, settings.hellVariant == .x9 ? 2000 : settings.hellVariant.bandwidthHz / 2 + 300)
            return .init(modulation: .usb, rfBandwidth: max(2400, center + settings.hellVariant.bandwidthHz / 2 + 200),
                         audioBand: "OOK · \(settings.hellVariant.rawValue) · centro \(Int(center)) Hz · ancho ocupado ≈\(Int(settings.hellVariant.bandwidthHz)) Hz", center: center,
                         note: receptionProfile.note)
        }
        if self == .mt63 {
            let center = settings.frequency.isFinite ? min(2500, max(1000, settings.frequency)) : 1500
            let half = Double(settings.mt63Variant.bandwidth) / 2
            return .init(modulation: .usb, rfBandwidth: max(3000, center + half + 200),
                         audioBand: "\(Int(center - half))–\(Int(center + half)) Hz · \(settings.mt63Variant.title) · PCM interno 8 kHz", center: center,
                         note: receptionProfile.note)
        }
        if self == .rtty || self == .bitAnalysis {
            // Text fields can contain unvalidated exponents while the user is
            // editing. Never convert those values directly to a display Int.
            let center = settings.frequency.isFinite && (1...192000).contains(settings.frequency) ? settings.frequency : 1500
            let shift = settings.shift.isFinite && (50...1000).contains(settings.shift) ? settings.shift : 170
            return .init(modulation: .usb, rfBandwidth: max(2400, center + shift / 2 + 200),
                         audioBand: "\(Int(center - shift / 2))/\(Int(center + shift / 2)) Hz · \(settings.rttyEncoding.rawValue) · \(settings.baud.formatted()) baud", center: center,
                         note: receptionProfile.note)
        }
        return receptionProfile
    }
    var receptionBandVariants: [ReceptionBandVariant] { self == .sstv ? [.hf, .vhf] : [.standard] }
    func signalModulation(settings: DecoderSettings) -> String {
        switch self {
        case .digitalVoice: settings.digitalVoiceProtocol.receptionPreset.signalModulation
        case .morse, .hell: "OOK · portadora interrumpida"
        case .rtty, .bitAnalysis, .navtex, .sitorA: "FSK de dos tonos"
        case .psk31: "BPSK · 31,25 símbolos/s"
        case .dtmf: "Dos tonos simultáneos"
        case .selectiveTones: "CTCSS · tono subaudio continuo"
        case .fiveTones: "Secuencia de tonos selectivos"
        case .pocsag: "FSK / NRZ · \(settings.pagerRate.title)"
        case .packet: "AFSK Bell 202 · 1200 baud · AX.25"
        case .acars: "MSK · 2400 bit/s en audio AM"
        case .ft8: "8-GFSK · trama de 15 s"
        case .ft4: "4-GFSK · trama de 7,5 s"
        case .sstv, .wefax: "FM de tonos de imagen en audio"
        case .satelliteAPT: "Subportadora AM 2400 Hz en audio FM"
        case .ale: "8-FSK · ALE 2G"
        case .mt63: "64 portadoras · fase diferencial"
        case .gmdss: settings.dscVariant == .vhf ? "AFSK · 1200 baud" : "FSK · 100 baud · shift 170 Hz"
        case .dgps: "MSK · integración pendiente"
        case .loran: "Pulsos RF · requiere evidencia I/Q adecuada"
        case .globeWireless: "Variante por identificar · sin motor verificado"
        }
    }
    var audioInputRecommendation: String {
        if self == .loran { return "Captura RF/IQ apropiada; el audio de altavoz no conserva los pulsos originales." }
        return "Entrada PCM mono 48 kHz recomendada. Elige el dispositivo y canal correctos; el motor remuestrea cuando corresponde. I/Q no es audio de entrada."
    }
    var receptionProfile: ReceptionProfile {
        switch self {
        case .ft8, .ft4: .init(modulation: .usb, rfBandwidth: 3500, audioBand: "100–3500 Hz; PCM remuestreado a 12 kHz", center: 1500, note: "USB en todas las bandas. Desactiva squelch y procesado de voz; reloj UTC sincronizado. FT8 15 s, FT4 7,5 s. En WAV indica el inicio de la primera ventana.")
        case .digitalVoice: .init(modulation: .fm, rfBandwidth: 12500, audioBand: "Discriminador NFM sin de-emphasis, PCM mono 48 kHz", center: 1500, note: "Selecciona el protocolo. SDR++: de-emphasis, squelch y filtros de voz desactivados. NXDN48 puede necesitar RF 6,25 kHz. Un único canal sintonizado; sin seguimiento de trunking ni control del SDR.")
        case .morse: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "Tono CW alrededor de 700 Hz", center: 700, note: "USB o CW; filtro estrecho solo si conserva el tono seleccionado.")
        case .rtty, .bitAnalysis: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "1415–1585 Hz para shift 170 y centro 1500", center: 1500, note: "LSB invierte la polaridad: activa Invertir si corresponde.")
        case .psk31: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "BPSK31 alrededor de 1500 Hz", center: 1500, note: "Desactiva supresión de ruido; sintonía precisa y sin deriva.")
        case .sstv: .init(modulation: .usb, rfBandwidth: 3000, audioBand: "1100–2300 Hz, conservar VIS y sincronía", center: 1900, note: "HF normalmente USB; en VHF puede usarse FM con filtro RF 12,5–25 kHz.")
        case .wefax: .init(modulation: .usb, rfBandwidth: 2800, audioBand: "1500 negro · 1900 gris · 2300 blanco", center: 1900, note: "Dial USB = portadora asignada − 1,9 kHz. Inicio manual; ajusta fase y reloj.")
        case .satelliteAPT: .init(modulation: .fm, rfBandwidth: 50000, audioBand: "Subportadora AM 2400 Hz; preservar audio hasta unos 4,5 kHz", center: 2400, note: "En SDR++ usa FM, 50 kHz RF, De-emphasis None, Low Pass off y Squelch off. NOAA APT: grabaciones históricas.")
        case .dtmf: .init(modulation: .fm, rfBandwidth: 12500, audioBand: "697–1633 Hz para DTMF", center: 1500, note: "Conserva ambas componentes del teclado; evita que el squelch corte los tonos.")
        case .pocsag: .init(modulation: .fm, rfBandwidth: 25000, audioBand: "Discriminador FM sin de-emphasis; conservar niveles y transiciones NRZ", center: 1500, note: "POCSAG 512/1200/2400. PCM mono ≥8 kHz, preferentemente 48 kHz; remuestreo interno a 22050 Hz. Desactiva de-emphasis, squelch, pasa-altos de voz y reducción de ruido. Una salida de altavoz filtrada puede perder datos.")
        case .fiveTones: .init(modulation: .fm, rfBandwidth: 12500, audioBand: "Tonos selectivos aproximadamente 500–2800 Hz según estándar", center: 1500, note: "Selecciona ZVEI/CCIR/EEA/EIA. Conserva la secuencia entera y deja squelch abierto. E/F pueden ser códigos especiales; se muestran tal como se recibieron.")
        case .selectiveTones: .init(modulation: .fm, rfBandwidth: 12500, audioBand: "50–300 Hz; CTCSS 67–254,1 Hz", center: 100, note: "NFM con audio que conserve subaudio. Desactiva el filtro pasa-altos de voz (300 Hz), squelch y reducción de ruido. Umbral inicial 2 %. Confirmación en unos 2,5 s; DCS pendiente. Cinco tonos tiene su propio apartado.")
        case .navtex: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "1615/1785 Hz; centro 1700 Hz y shift 170 Hz", center: 1700, note: "100 baud síncronos. Conserva ambos tonos; LSB requiere Invertir. Espera phasing al comienzo. Ajusta centro si tu audio usa otros tonos.")
        case .sitorA: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "Dos tonos separados 170 Hz", center: 1700, note: "SITOR-A: bloques ARQ a 100 baud. Motor aún pendiente.")
        case .acars: .init(modulation: .am, rfBandwidth: 12500, audioBand: "Audio AM 300–3500 Hz; MSK 1200/2400 Hz", center: 1800, note: "VHF ACARS 2400 baud. RF inicial 10–12,5 kHz; salida 48 kHz, sin squelch ni reducción de ruido. La app remuestrea a 12 kHz. ACARS no es VDL2 ni ADS-B.")
        case .packet: .init(modulation: .fm, rfBandwidth: 12500, audioBand: "300–3000 Hz; AFSK 1200/2200 Hz, 1200 baud", center: 1700, note: "VHF/APRS: NFM 12–15 kHz, squelch abierto. Centro de audio 1700 Hz. Este motor recibe AFSK 1200; HF 300 y 9600 requieren otros demoduladores.")
        case .ale: .init(modulation: .usb, rfBandwidth: 3000, audioBand: "Ocho tonos fijos 750–2500 Hz · ALE 2G · PCM interno 8 kHz", center: 1625, note: "SDR++: USB, filtro de 3 kHz, squelch y reducción de ruido desactivados. Conserva los ocho tonos; la sintonía se ajusta en el SDR. Recibe sondeos, llamadas y AMD; ALE 3G requiere otro motor.")
        case .hell: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "OOK alrededor del centro elegido; Feld ≈350 Hz, Slow ≈40–44 Hz", center: 1500, note: "Raster visual, sin OCR ni cabecera. Ajusta inicio y reloj si el texto se inclina. X5 necesita ≈1750 Hz y X9 ≈3150 Hz ocupados: amplía RF y usa centro ≥2000 Hz para X9. No incluye FSK-Hell ni Hell 80.")
        case .mt63: .init(modulation: .usb, rfBandwidth: 3000, audioBand: "Ancho 500/1000/2000 Hz y entrelazado corto/largo seleccionables", center: 1500, note: "USB; conserva todo el bloque multicarrier, sin squelch ni procesado de voz. A centro 1500 Hz: 1250–1750 / 1000–2000 / 500–2500 Hz según ancho. Espera la adquisición y el entrelazado antes del texto; no estima SNR ni incorpora CRC de mensaje.")
        case .gmdss: .init(modulation: .usb, rfBandwidth: 2400, audioBand: "DSC MF/HF: 170 Hz de shift; VHF: tonos 1300/2100 Hz", center: 1700, note: "Para DSC VHF selecciona FM y filtro RF inicial de 16 kHz (ampliable si hace falta). Deja squelch abierto y conserva la ráfaga completa. GMDSS abarca más que DSC.")
        case .dgps: .init(modulation: .usb, rfBandwidth: 1500, audioBand: "MSK trasladada a audio; centro 800 Hz inicial", center: 800, note: "Preset inicial; validar 100/200 baud y sintonía con el motor DGPS.")
        case .loran: .init(modulation: .iq, rfBandwidth: 20000, audioBand: "Pulsos RF; audio convencional no conserva toda la información", center: 1000, note: "El monitor de pulsos requiere captura adecuada, no una salida FM de voz.")
        case .globeWireless: .init(modulation: .usb, rfBandwidth: 3000, audioBand: "Depende de variante; sin motor verificado", center: 1500, note: "Parámetros iniciales de exploración, no soporte de protocolo confirmado.")
        }
    }
}
