import SwiftUI
import RadioCore

struct InputQualityView: View {
    @Bindable var receiver: ReceiverStore
    var body: some View {
        DisclosureGroup("Diagnóstico de entrada y calidad") {
            VStack(alignment: .leading, spacing: 8) {
                if let frame = receiver.frame {
                    let q = frame.quality
                    Text("Último bloque analizado: \(q.sampleCount) muestras · \(frame.sampleRate.formatted()) Hz · \(receiver.settings.audioChannel.label)")
                    Text("RMS \(frame.levelDB.formatted(.number.precision(.fractionLength(1)))) dBFS · pico \(q.peak.formatted(.number.precision(.fractionLength(3)))) · DC \(q.dc.formatted(.number.precision(.fractionLength(4))))")
                        .monospacedDigit()
                    let findings = InputQualityAssessment.findings(frame: frame, mode: receiver.mode, settings: receiver.settings,
                                                                  dropped: receiver.dropped, received: receiver.samplesReceived)
                    if findings.isEmpty { Label("Sin problemas de nivel o formato detectados en este bloque.", systemImage: "checkmark.circle") }
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(finding.observation, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(finding.action).foregroundStyle(.secondary)
                        }
                    }
                    Text(integrity).textSelection(.enabled)
                    Text("El nivel se mide en audio digital. No estima potencia RF, SNR de radio ni porcentaje de mensajes perdidos. Sin sincronía no se puede conocer cuántos paquetes se transmitieron. La saturación y el DC describen solo el bloque visible; las muestras descartadas corresponden a la sesión.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Abre un audio o inicia la entrada elegida para medir nivel, saturación y formato. No se inicia el micrófono desde este diagnóstico.").foregroundStyle(.secondary)
                }
            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        }
    }
    private var integrity: String {
        switch receiver.mode {
        case .packet: "Integridad AX.25: el monitor informa tramas aceptadas por CRC y descartes detectados; no calcula pérdida de paquetes enviados."
        case .acars: "\(receiver.acarsMessages.count) mensajes visibles con CRC del motor ACARS válido; \(receiver.acarsMessages.reduce(0) { $0 + $1.parityCorrections }) correcciones de paridad en esos mensajes. Retención limitada a 200."
        case .ft8, .ft4: "\(receiver.engineRecords.count) mensajes visibles con LDPC y CRC verificados. Retención limitada a 200; el motor no publica el total de transmisiones intentadas."
        case .pocsag: "POCSAG usa BCH/paridad y sincronismo periódico; el límite de corrección elegido es \(receiver.settings.pagerCorrectionBits) bits. Los \(receiver.multimonRecords.count) eventos visibles no representan una tasa de error."
        case .gmdss: "DSC: \(receiver.engineRecords.count) tramas visibles con ECC aceptado. La diversidad y la paridad de símbolos no autentican el mensaje; las discrepancias no equivalen a BER ni a símbolos corregidos."
        case .navtex: "NAVTEX: redundancia FEC de caracteres; no dispone de CRC global que certifique el texto completo."
        case .mt63: "MT63: sincronía y FEC del motor, sin CRC global de mensaje ni SNR calibrado."
        default: "Este modo no expone un contador de paquetes verificados. El espectro por sí solo no confirma decodificación correcta."
        }
    }
}
