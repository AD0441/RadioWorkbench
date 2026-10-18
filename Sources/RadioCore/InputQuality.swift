import Foundation

/// Measurements describe one analyzed PCM block, before any decoder filters.
/// They are not RF power, a calibrated SNR or a protocol error rate.
public struct AudioBlockQuality: Sendable {
    public let sampleCount: Int
    public let clippedCount: Int
    public let invalidCount: Int
    public let peak: Double
    public let dc: Double
    public let rms: Double
    public var clippedPercent: Double { sampleCount > 0 ? 100 * Double(clippedCount) / Double(sampleCount) : 0 }
    public init(samples: [Float]) {
        sampleCount = samples.count
        var clipped = 0, invalid = 0, maximum = 0.0, sum = 0.0, squares = 0.0
        for sample in samples {
            guard sample.isFinite else { invalid += 1; continue }
            let value = Double(sample)
            maximum = max(maximum, abs(value)); sum += value; squares += value * value
            if abs(value) >= 0.999 { clipped += 1 }
        }
        clippedCount = clipped; invalidCount = invalid; peak = maximum
        dc = samples.isEmpty ? 0 : sum / Double(samples.count)
        rms = samples.isEmpty ? 0 : sqrt(squares / Double(samples.count))
    }
}

public struct InputQualityFinding: Identifiable, Sendable {
    public let id: String
    public let observation: String
    public let action: String
}

public enum InputQualityAssessment {
    public static func findings(frame: SpectrumFrame, mode: RadioMode, settings: DecoderSettings,
                                dropped: UInt64, received: UInt64) -> [InputQualityFinding] {
        var findings: [InputQualityFinding] = []
        let q = frame.quality
        if q.invalidCount > 0 {
            findings.append(.init(id: "nonfinite", observation: "\(q.invalidCount) muestras no válidas en el bloque.", action: "Revisa el formato de la fuente; esas muestras se excluyeron del espectro."))
        }
        if q.rms < 0.000316 && q.sampleCount > 0 {
            findings.append(.init(id: "quiet", observation: "Nivel inferior a −70 dBFS en este bloque.", action: "Comprueba la entrada elegida, el canal y el volumen de salida. El silencio entre transmisiones también produce este resultado."))
        }
        if q.clippedCount > 0 {
            findings.append(.init(id: "clipping", observation: String(format: "%.2f %% de muestras al límite digital en el bloque.", q.clippedPercent), action: "Baja la ganancia antes de grabar o enviar el audio. Reducir volumen aquí no recupera los picos recortados."))
        }
        if abs(q.dc) > 0.1 {
            findings.append(.init(id: "dc", observation: String(format: "Desplazamiento DC %.3f de escala completa.", q.dc), action: "Comprueba la salida del discriminador y el formato PCM; evita filtros de voz que eliminen datos de baja frecuencia."))
        }
        if dropped > 0 {
            let percent = received > 0 ? String(format: " (%.2f %%)", 100 * Double(dropped) / Double(received)) : ""
            findings.append(.init(id: "drops", observation: "\(dropped) muestras descartadas en esta sesión\(percent).", action: "Reduce otras cargas del Mac. El receptor reinicia sincronía al detectar una interrupción; TCP no permite atribuirla a pérdida de paquetes de red."))
        }
        do { try settings.validated(sampleRate: frame.sampleRate, mode: mode) }
        catch {
            findings.append(.init(id: "settings", observation: error.localizedDescription, action: "Ajusta los parámetros o usa una fuente con tasa suficiente antes de repetir la decodificación."))
        }
        return findings
    }
}
