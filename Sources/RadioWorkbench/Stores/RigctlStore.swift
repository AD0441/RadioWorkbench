import Foundation
import Observation
import RadioCore

@MainActor @Observable final class RigctlStore {
    var enabled = false
    var port: UInt16 = 4532
    var frequencyMHz = ""
    var modulation: RFModulation = .usb
    var bandwidthHz = 2400
    var source = "Parámetros manuales"
    var state: RigctlState?
    var busy = false
    var error: String?
    var status = "Habilita Rigctl en SDR++, selecciona el VFO y permite sintonía si quieres usar esta opción."
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    func prepare(mhz: Double, modulation: RFModulation, bandwidth: Double, source: String) {
        task?.cancel(); task = nil; generation = UUID(); busy = false
        frequencyMHz = String(mhz); self.modulation = modulation; bandwidthHz = Int(bandwidth)
        self.source = source; state = nil; error = nil
        status = "Propuesta preparada; revisa los valores y comprueba la conexión."
    }
    func perform(apply: Bool) {
        guard enabled, !busy else { return }
        let request: RigctlRequest?
        if apply {
            guard let mhz = RadioNumericText.frequencyMHz(frequencyMHz) else { error = RigctlError.invalidInput.localizedDescription; return }
            request = .init(frequencyHz: mhz * 1_000_000, modulation: modulation, bandwidthHz: bandwidthHz)
        } else { request = nil }
        let token = UUID(); generation = token
        busy = true; error = nil
        task = Task {
            defer { if token == generation { busy = false; task = nil } }
            do {
                let result = try await RigctlClient.perform(port: port, request: request)
                try Task.checkCancellation(); guard generation == token else { return }; state = result
                status = apply ? "Frecuencia, modo y ancho confirmados con una nueva lectura del SDR." : "Conexión comprobada mediante lectura; no se enviaron ajustes."
            } catch is CancellationError { guard token == generation else { return }; status = "Consulta cancelada. Revisa el estado del SDR si interrumpiste una sintonía." }
            catch { guard token == generation else { return }; self.error = error.localizedDescription; status = "La operación no quedó confirmada." }
        }
    }
    func cancel() { task?.cancel() }
}
