import Foundation

/// Initial channel setup, distinct from the occupied bandwidth and from a voice
/// recording. DSD receives the demodulated discriminator, resampled to mono 48 kHz.
public struct DigitalVoiceReceptionPreset: Sendable {
    public let rfBandwidthHz: Double
    public let signalModulation: String
    public let note: String
    public let sourceTitle: String
    public let sourceURL: URL
    public var sampleRate: Double { 48000 }
    public var channels: Int { 1 }
    public var modulation: RFModulation { .fm }
    public var audioDescription: String { "Discriminador NFM sin de-emphasis · PCM mono · 48 kHz al motor" }
    public var profile: ReceptionProfile {
        .init(modulation: modulation, rfBandwidth: rfBandwidthHz, audioBand: audioDescription,
              center: 0, note: note + " Desactiva squelch, pasa-altos, reducción de ruido y filtros de voz. Ajusta el canal RF en el SDR; DSD no usa un tono central de audio.")
    }
}

public extension DigitalVoiceProtocol {
    var receptionPreset: DigitalVoiceReceptionPreset {
        switch self {
        case .dmr:
            .init(rfBandwidthHz: 12500, signalModulation: "4FSK · dos intervalos TDMA",
                  note: "TS1 y TS2 comparten un canal RF de 12,5 kHz. Selecciona el intervalo de voz antes de iniciar.",
                  sourceTitle: "DMR Association · estándar ETSI", sourceURL: URL(string: "https://dmrassociation.org/dmr-standards.html")!)
        case .p25p1:
            .init(rfBandwidthHz: 12500, signalModulation: "C4FM; existen sistemas LSM/CQPSK",
                  note: "Canal de 12,5 kHz. Este recorrido usa audio de discriminador; una señal LSM/CQPSK puede necesitar otro demodulador y captura I/Q.",
                  sourceTitle: "Tait · P25 fases I y II", sourceURL: URL(string: "https://www.taitcommunications.com/en/about-us/news/2013/09/19/p25-radio-frequently-asked-questions")!)
        case .p25p2:
            .init(rfBandwidthHz: 12500, signalModulation: "TDMA · dos intervalos en 12,5 kHz",
                  note: "Canal RF completo de 12,5 kHz, no filtro de 6,25 kHz. Recepción del canal seleccionado; sin seguimiento automático de la red troncal.",
                  sourceTitle: "Tait · P25 fase II", sourceURL: URL(string: "https://www.taitcommunications.com/p25-phase-2")!)
        case .nxdn48:
            .init(rfBandwidthHz: 6250, signalModulation: "4FSK · 4800 bit/s",
                  note: "Variante de canal 6,25 kHz; no confundir con NXDN 9600. Afina la frecuencia RF si la señal queda descentrada.",
                  sourceTitle: "NXDN Forum · especificaciones", sourceURL: URL(string: "https://www.nxdn-forum.com/what-is-nxdn/technical-specifications-of-nxdn/")!)
        case .nxdn96:
            .init(rfBandwidthHz: 12500, signalModulation: "4FSK · 9600 bit/s",
                  note: "Variante de canal 12,5 kHz; selecciona NXDN 4800 para emisiones de 6,25 kHz.",
                  sourceTitle: "NXDN Forum · especificaciones", sourceURL: URL(string: "https://www.nxdn-forum.com/what-is-nxdn/technical-specifications-of-nxdn/")!)
        case .dstar:
            .init(rfBandwidthHz: 6250, signalModulation: "GMSK · voz digital DV",
                  note: "Perfil inicial para D-STAR DV de banda estrecha; el modo de datos DD no corresponde a esta entrada.",
                  sourceTitle: "JARL · especificaciones D-STAR", sourceURL: URL(string: "https://www.jarl.com/d-star/shogen.htm")!)
        case .ysf:
            .init(rfBandwidthHz: 12500, signalModulation: "C4FM · System Fusion",
                  note: "Conserva el canal RF de 12,5 kHz también en Digital Narrow; ese nombre no indica un filtro RF de 6,25 kHz.",
                  sourceTitle: "Yaesu · System Fusion", sourceURL: URL(string: "https://yaesu.com/pdf/VHF_UHF_AMATEUR_EQUIPMENT_CATALOG_201704.pdf")!)
        case .m17:
            .init(rfBandwidthHz: 12500, signalModulation: "4FSK · voz o paquetes de datos",
                  note: "Filtro inicial de canal 12,5 kHz; ancho ocupado aproximado 9 kHz. El ejemplo incluido transporta datos, no una conversación de voz.",
                  sourceTitle: "M17 Project · especificación", sourceURL: URL(string: "https://spec.m17project.org/")!)
        case .dpmr:
            .init(rfBandwidthHz: 6250, signalModulation: "4FSK · FDMA",
                  note: "dPMR usa un canal real de 6,25 kHz; no es el modo DMR de dos intervalos.",
                  sourceTitle: "dPMR Association · descripción", sourceURL: URL(string: "https://dpmrassociation.org/dPMR-a-brief-overview.html")!)
        }
    }
}
