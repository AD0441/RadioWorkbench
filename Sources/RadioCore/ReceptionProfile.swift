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
}

public extension RadioMode {
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
