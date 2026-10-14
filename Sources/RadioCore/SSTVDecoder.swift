import Foundation

// N7CXI timings/BT.601 and JE3HHT's MMSSTV timing/header specifications.
final class SSTVDecoder {
    private let settings: DecoderSettings
    private var clockCorrection: Double
    private var headerState = 0, vis = 0, visBit = 0, parity = 0
    private var held = 0.0, previousTime = 0.0, dataStart = 0.0, nextBit = 0.0
    private var extended = false
    private var narrowState = 0, narrowBits = 0, narrowWord = 0
    private var narrowHeld = 0.0, narrowOther = 0.0, narrowStart = 0.0, narrowNext = 0.0
    private var bodyStart: Double?
    private var activeFormat: SSTVFormat = .automatic
    private var descriptor: SSTVDescriptor?
    private var windows: [(start: Double, duration: Double, plane: Int, rowOffset: Int)] = []
    private var pixels: [UInt8] = []
    private var channelSums: [Double] = []
    private var channelCounts: [UInt16] = []
    private var height = 0
    private var headerStarted = 0.0, narrowStarted = 0.0
    private var nonstandardParity = false
    private var message = "Buscando cabecera VIS…"
    private struct VideoSample { let frequency: Float, amplitude: Float; let time: Double }
    private var timeline: [VideoSample] = []
    private var tracker: SSTVTimingTracker?
    private var carrierEstimates: [Double] = []
    private var headerTone = 0.0, frequencyDelta = 0.0
    private var cleanPixels: [UInt8]?
    private(set) var rasterGeneration = 0
    private(set) var calibration: SSTVCalibration?
    var status: String {
        message + (calibration.map { " · reloj auto \(Int($0.clockPPM.rounded())) ppm · centro \(Int($0.centerHz.rounded())) Hz · \($0.syncLines) sincronías" } ?? "")
    }
    var syncTone: Double? {
        guard settings.sstvAutoCalibrate, bodyStart != nil, let descriptor else { return nil }
        return (descriptor.identification == .narrow24 ? 1900 : 1200) + settings.frequency - 1900 + frequencyDelta
    }
    var measuringLeader: Bool { settings.sstvAutoCalibrate && bodyStart == nil && headerTone == 1900 }
    func observeCarrier(_ frequency: Double) {
        guard measuringLeader, frequency.isFinite else { return }
        if carrierEstimates.count == 16 { carrierEstimates.removeFirst() }
        carrierEstimates.append(frequency)
    }
    init(sampleRate: Double, settings: DecoderSettings) {
        self.settings = settings
        clockCorrection = 1 + settings.imageClockPPM * 0.000001
        if !settings.imageAutoSync {
            activeFormat = settings.sstvFormat == .automatic ? .martinM1 : settings.sstvFormat
            resetRaster(); bodyStart = settings.imageStartSeconds; beginTracking(); message = "\(activeFormat.rawValue) · inicio manual"
        }
    }
    func observeHeader(frequency: Double, amplitude: Double, time: Double) {
        guard bodyStart == nil, settings.imageAutoSync else { return }
        let dt = time - previousTime; previousTime = time; headerTone = frequency
        // A late line-sync pulse must not stand in for a missing VIS stop bit.
        let stopDeadline = dataStart + ((extended ? 0.510 : 0.270) - 0.005) / clockCorrection
        if headerState == 5, time > stopDeadline {
            headerState = 0; held = 0; message = "Stop VIS inválido; buscando cabecera"; return
        }
        if headerState > 0, time - headerStarted > 2 { headerState = 0; held = 0; message = "Cabecera incompleta · buscando VIS…" }
        if narrowState > 0, time - narrowStarted > 2 { narrowState = 0; narrowHeld = 0; narrowOther = 0 }
        guard amplitude >= settings.threshold / 2 else {
            held = max(0, held - 4 * min(0.005, dt)); narrowHeld = max(0, narrowHeld - 4 * min(0.005, dt)); return
        }
        detectVIS(frequency: frequency, time: time, dt: min(0.005, dt))
        if bodyStart == nil { detectNarrowVIS(frequency: frequency, time: time, dt: min(0.005, dt)) }
    }
    func push(frequency: Double, amplitude: Double, time: Double) {
        guard frequency.isFinite else { return }
        guard let descriptor, bodyStart != nil else { return }
        if settings.sstvAutoCalibrate {
            let limit = Int(descriptor.period * Double(descriptor.height) / (descriptor.paired ? 2 : 1) * 12000 * 1.07) + 512
            if timeline.count < limit { timeline.append(VideoSample(frequency: Float(frequency), amplitude: Float(amplitude), time: time)) }
        }
        rasterize(frequency: frequency - frequencyDelta, amplitude: amplitude, time: time)
    }
    private func rasterize(frequency: Double, amplitude: Double, time: Double) {
        guard let start = bodyStart else { return }
        guard let descriptor else { return }
        let elapsed = (time - start) * clockCorrection - descriptor.initialSync
        guard elapsed >= 0 else { return }
        let block = Int(elapsed / descriptor.period)
        let firstRow = descriptor.paired ? block * 2 : block
        guard firstRow < descriptor.height else {
            message = "\(activeFormat.rawValue) · imagen completa \(descriptor.width) × \(descriptor.height)" + (nonstandardParity ? " · paridad VIS no estándar" : "")
            if cleanPixels == nil { cleanPixels = SSTVImageFilter.apply(pixels, width: descriptor.width, height: descriptor.height, reduction: settings.sstvNoiseReduction) }
            if settings.imageAutoSync { bodyStart = nil; headerState = 0; held = 0; narrowState = 0; narrowHeld = 0 }
            return
        }
        guard amplitude >= settings.threshold / 2 else { return }
        let offset = elapsed - Double(block) * descriptor.period
        for window in windows where offset >= window.start && offset < window.start + window.duration {
            let row = firstRow + window.rowOffset
            let column = min(descriptor.width - 1, Int((offset - window.start) / window.duration * Double(descriptor.width)))
            var plane = window.plane
            if descriptor.family == .robot36 && plane == 1 { plane = row % 2 == 0 ? 1 : 2 }
            let target = (row * descriptor.width + column) * 3 + plane
            // Average phase noise before limiting levels. Clamping every sample
            // biases noisy black upward and noisy white downward.
            channelSums[target] += (frequency - descriptor.black) / descriptor.toneSpan * 255
            channelCounts[target] &+= 1
            if descriptor.colorDifference {
                colorize(row: row, column: column)
                if descriptor.paired || descriptor.family == .robot36 { colorize(row: row ^ 1, column: column) }
            } else {
                pixels[target] = UInt8(min(255, max(0, channelSums[target] / Double(max(1, channelCounts[target])))))
            }
            height = max(height, min(descriptor.height, row + 1))
        }
    }
    func observeSync(center: Double, duration: Double) {
        guard settings.sstvAutoCalibrate, let descriptor, bodyStart != nil,
              duration >= max(0.0015, descriptor.sync * 0.25), duration <= descriptor.sync / clockCorrection + 0.006 else { return }
        let pulseStart = center - descriptor.sync / (2 * clockCorrection)
        guard let fit = tracker?.observe(pulseStart) else { return }
        let correction = descriptor.period / fit.period
        let newStart = fit.anchor - (descriptor.initialSync + descriptor.lineSyncOffset) / correction
        // Keep exact nominal timing for negligible drift; avoid injecting
        // sub-millisecond pulse estimator jitter into clean transmissions.
        let changed = abs(correction - clockCorrection) > 0.00005 || (abs(correction - 1) > 0.0002 && abs(newStart - (bodyStart ?? newStart)) > 0.0002)
        calibration = SSTVCalibration(clockPPM: (correction - 1) * 1e6, centerHz: settings.frequency + frequencyDelta,
                                      syncLines: fit.count, jitterMilliseconds: fit.residual * 1000)
        guard changed else { return }
        clockCorrection = correction
        if abs(correction - 1) > 0.0002 { bodyStart = newStart }
        resetRaster(replaying: true)
        for value in timeline { rasterize(frequency: Double(value.frequency) - frequencyDelta, amplitude: Double(value.amplitude), time: value.time) }
    }
    private func resetRaster(replaying: Bool = false) {
        descriptor = activeFormat.descriptor
        guard let descriptor else { return }
        windows = descriptor.windows
        cleanPixels = nil
        if !replaying {
            rasterGeneration += 1; timeline.removeAll(keepingCapacity: true); calibration = nil
            clockCorrection = 1 + settings.imageClockPPM * 0.000001
            if settings.sstvAutoCalibrate, !carrierEstimates.isEmpty {
                let sorted = carrierEstimates.sorted(); frequencyDelta = sorted[sorted.count / 2] - 1900
            } else { frequencyDelta = 0 }
            carrierEstimates.removeAll(keepingCapacity: true)
        }
        let count = descriptor.width * descriptor.height * 3
        pixels = Array(repeating: 0, count: count)
        channelSums = Array(repeating: 0, count: count)
        channelCounts = Array(repeating: 0, count: count)
        height = 0
    }
    private func colorize(row: Int, column: Int) {
        guard let descriptor, row >= 0, row < descriptor.height else { return }
        let base = (row * descriptor.width + column) * 3
        let chromaRow = descriptor.paired || descriptor.family == .robot36 ? row & ~1 : row
        let crBase = (chromaRow * descriptor.width + column) * 3 + 1
        let cbRow = descriptor.family == .robot36 ? chromaRow + 1 : chromaRow
        let cbBase = (cbRow * descriptor.width + column) * 3 + 2
        func value(_ i: Int, fallback: Double) -> Double {
            channelCounts[i] == 0 ? fallback : min(255, max(0, channelSums[i] / Double(channelCounts[i])))
        }
        let y = value(base, fallback: 0)
        let cr = value(crBase, fallback: 128) - 128
        let cb = value(cbBase, fallback: 128) - 128
        let red: Double, green: Double, blue: Double
        if settings.sstvColorRange == .bt601 {
            let luminance = 298.082 * (y - 16)
            red = 0.003906 * (luminance + 408.583 * cr)
            green = 0.003906 * (luminance - 100.291 * cb - 208.120 * cr)
            blue = 0.003906 * (luminance + 516.411 * cb)
        } else {
            red = y + 1.402 * cr
            green = y - 0.714136 * cr - 0.344136 * cb
            blue = y + 1.772 * cb
        }
        pixels[base] = UInt8(min(255, max(0, red)).rounded())
        pixels[base + 1] = UInt8(min(255, max(0, green)).rounded())
        pixels[base + 2] = UInt8(min(255, max(0, blue)).rounded())
    }
    private func detectVIS(frequency f: Double, time: Double, dt: Double) {
        switch headerState {
        case 0:
            if abs(f - 1900) < 70 { held += dt; if held > 0.20 {
                headerState = 1; held = 0; headerStarted = time; nonstandardParity = false
                message = "Tono de inicio detectado · esperando VIS…"
            } }
            else { held = max(0, held - 4 * dt) }
        case 1:
            if abs(f - 1200) < 65 { held += dt }
            else if abs(f - 1900) < 70 && held >= 0.005 { headerState = 2; held = dt }
        case 2:
            if abs(f - 1900) < 70 { held += dt; if held > 0.20 { headerState = 3; held = 0 } }
        case 3:
            if abs(f - 1200) < 55 { held += dt }
            else if held >= 0.02 && (abs(f - 1100) < 65 || abs(f - 1300) < 65) {
                headerState = 4; dataStart = time; nextBit = time + 0.015 / clockCorrection; visBit = 0; vis = 0; parity = 0; extended = false
                message = "Cabecera SSTV · leyendo VIS…"
            }
        case 4:
            if time >= nextBit {
                let bit = abs(f - 1100) < abs(f - 1300) ? 1 : 0
                if visBit == 7 && vis == 0x23 { extended = true }
                if visBit < 7 || extended { vis |= bit << visBit; if visBit < 7 { parity ^= bit } }
                else if parity != bit {
                    if settings.sstvRobot36Compatibility, (settings.sstvFormat == .robot36 || settings.imageAutoSync), vis == 8 {
                        nonstandardParity = true
                    } else { headerState = 0; held = 0; message = "VIS con paridad incorrecta; buscando otra cabecera"; return }
                }
                visBit += 1; nextBit += 0.03 / clockCorrection
                if visBit == (extended ? 16 : 8) {
                    let identification: SSTVDescriptor.Identification = extended ? .extended16 : .vis7
                    if let format = SSTVFormat.allCases.first(where: { $0.descriptor?.vis == vis && $0.descriptor?.identification == identification }) {
                        activeFormat = format
                        headerState = 5
                    } else { message = "VIS \(vis): formato todavía no implementado"; headerState = 0; held = 0 }
                }
            }
        case 5:
            let duration = (extended ? 0.510 : 0.270) / clockCorrection
            if time >= dataStart + duration - 0.015 / clockCorrection {
                if abs(f - 1200) < 90 {
                    resetRaster(); bodyStart = dataStart + duration; beginTracking()
                    message = "\(activeFormat.rawValue) · VIS \(vis) " + (nonstandardParity ? "con paridad no estándar" : "válido")
                } else { headerState = 0; held = 0; message = "Stop VIS inválido; buscando cabecera" }
            }
        default: break
        }
    }
    private func detectNarrowVIS(frequency f: Double, time: Double, dt: Double) {
        switch narrowState {
        case 0:
            if abs(f - 1900) < 55 { narrowHeld += dt; if narrowHeld > 0.20 { narrowState = 1; narrowHeld = 0; narrowOther = 0; narrowStarted = time } }
            else { narrowHeld = max(0, narrowHeld - 4 * dt) }
        case 1:
            if abs(f - 2100) < 55 { narrowHeld += dt; narrowOther = 0 }
            else if abs(f - 1900) < 55 && narrowHeld >= 0.085 {
                narrowStart = time + 0.022 / clockCorrection; narrowNext = narrowStart + 0.011 / clockCorrection
                narrowState = 2; narrowBits = 0; narrowWord = 0
            } else if abs(f - 1900) < 55 { narrowHeld = 0; narrowOther = 0 }
            else { narrowOther += dt; if narrowOther > 0.020 { narrowState = 0; narrowHeld = 0 } }
        case 2:
            if time >= narrowNext {
                let bit = abs(f - 1900) < abs(f - 2100) ? 1 : 0
                narrowWord = (narrowWord << 1) | bit
                narrowBits += 1; narrowNext += 0.022 / clockCorrection
                if narrowBits == 24 {
                    let a = (narrowWord >> 18) & 63, b = (narrowWord >> 12) & 63
                    let code = (narrowWord >> 6) & 63, checksum = narrowWord & 63
                    if a == 0b101101 && b == 0b010101 && checksum == (0b010101 ^ code),
                       let format = SSTVFormat.allCases.first(where: { $0.descriptor?.identification == .narrow24 && $0.descriptor?.vis == code }) {
                        activeFormat = format; resetRaster(); bodyStart = narrowStart + 24 * 0.022 / clockCorrection; beginTracking()
                        message = "\(format.rawValue) · N-VIS \(code) válido"
                    } else { message = "N-VIS inválido o formato no implementado; buscando cabecera" }
                    narrowState = 0; narrowHeld = 0
                }
            }
        default: break
        }
    }
    private func beginTracking() {
        guard let descriptor, let start = bodyStart else { return }
        tracker = SSTVTimingTracker(period: descriptor.period,
            anchor: start + (descriptor.initialSync + descriptor.lineSyncOffset) / clockCorrection, correction: clockCorrection)
    }
    var image: RadioImage? {
        guard height > 0, let descriptor else { return nil }
        return RadioImage(width: descriptor.width, height: height, rgb: Array((cleanPixels ?? pixels).prefix(height * descriptor.width * 3)), caption: status)
    }
}
