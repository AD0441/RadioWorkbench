import Foundation

// Passive Mode-A monitor, not an ARQ terminal. Protocol facts are from
// ITU-R M.476-5 Annex 1 §§1, 2.2, 3.1.1–3.1.6 and Figures 1–2:
// https://www.itu.int/dms_pubrec/itu-r/rec/m/R-REC-M.476-5-199510-I!!PDF-E.pdf
// Three 7-bit words occupy 210 ms of a 450 ms cycle. A return control is
// a separate 70 ms burst; its value alone is insufficient (CS1 is also L).
// Every accepted word satisfies 4B/3Y, which detects some errors, not all.
final class SITORABlockReceiver {
    static let cs1: UInt8 = 0x65, cs2: UInt8 = 0x6A, cs3: UInt8 = 0x59
    static let beta: UInt8 = 0x33
    private struct Block {
        let words: [UInt8]?
        let start: Double
        let request: UInt8?
        var response: UInt8?
        var acknowledged = false
    }
    private var acquisition: [Block] = []
    private var lastBlock: Block?
    private var nextRequest: UInt8?
    private var figures = false
    private var invalidRun = 0, repeatRun = 0
    private(set) var locked = false
    private(set) var text = ""
    private(set) var acceptedBlocks = 0, invalidBlocks = 0, rejectedBursts = 0
    private(set) var acknowledgements = 0, retransmissions = 0, ambiguousDuplicates = 0
    private(set) var controls = 0, changesOfDirection = 0, resynchronizations = 0

    /// A complete, time delimited burst. Nil denotes an uncertain word.
    /// The audio layer also rejects bursts with ambiguous bit alignment.
    func receive(words: [UInt8?], start: Double, duration: Double) {
        guard start.isFinite, duration.isFinite else { return }
        advance(to: start)
        if words.count == 1, (0.058...0.082).contains(duration), let code = words[0],
           [Self.cs1, Self.cs2, Self.cs3, CCIR476.repeatSignal].contains(code) {
            receiveControl(code, start: start)
            return
        }
        guard words.count == 3, (0.193...0.227).contains(duration) else {
            rejectedBursts += 1
            return
        }
        let valid = words.allSatisfy { $0.map(CCIR476.valid) ?? false }
        let codes = valid ? words.compactMap { $0 } : nil
        if let previous = lastBlock, abs(start - previous.start - 0.450) > 0.018 {
            loseLock()
        }
        let block = Block(words: codes, start: start, request: nextRequest)
        nextRequest = nil
        if !locked {
            // Timing and three constant-weight words must agree in three
            // successive cycles. A continuous SITOR-B stream cannot acquire.
            guard valid else { acquisition.removeAll(keepingCapacity: true); lastBlock = block; return }
            acquisition.append(block)
            if acquisition.count > 3 { acquisition.removeFirst() }
            if acquisition.count == 3 {
                locked = true; figures = false
                let primed = acquisition
                acquisition.removeAll(keepingCapacity: true)
                lastBlock = nil
                for item in primed {
                    guard locked else { break }
                    publish(item)
                }
            } else { lastBlock = block }
            return
        }
        publish(block)
    }

    private func receiveControl(_ code: UInt8, start: Double) {
        if let previous = lastBlock {
            // Controls must lie in the receive pause, not inside another
            // three-word information burst. A response may be inaudible.
            let offset = start - previous.start
            guard offset >= 0.207, offset + 0.070 <= 0.453 else { rejectedBursts += 1; return }
            guard previous.response == nil else { rejectedBursts += 1; return }
            controls += 1
            if code == Self.cs3 || code == CCIR476.repeatSignal {
                if code == Self.cs3 { changesOfDirection += 1 }
                loseLock()
                return
            }
            var updated = previous
            updated.response = code
            if let request = previous.request, code != request, !previous.acknowledged {
                updated.acknowledged = true
                if locked, previous.words != nil { acknowledgements += 1 }
            }
            lastBlock = updated
            if !locked, !acquisition.isEmpty { acquisition[acquisition.count - 1] = updated }
        } else {
            controls += 1
        }
        nextRequest = code == Self.cs1 || code == Self.cs2 ? code : nil
    }

    private func publish(_ block: Block) {
        defer { if locked { lastBlock = block } }
        guard let words = block.words else {
            invalidBlocks += 1; invalidRun += 1; append("�")
            if invalidRun >= 3 { loseLock() }
            return
        }
        invalidRun = 0
        if words == [CCIR476.alpha, CCIR476.alpha, CCIR476.alpha] {
            loseLock(); return
        }
        if words == [Self.beta, CCIR476.alpha, Self.beta] {
            changesOfDirection += 1; loseLock(); return
        }
        // RQ is service information. No part of an RQ/call block is printed.
        if words.contains(CCIR476.repeatSignal) { return }
        if let previous = lastBlock, let old = previous.words, old == words {
            if let request = previous.request, previous.response == request, block.request == request {
                retransmissions += 1; repeatRun += 1
                if repeatRun >= 32 { loseLock() }
                return
            }
            // Without the return channel equal payloads are ambiguous: they
            // may be legitimate repeated text. Never silently delete them.
            ambiguousDuplicates += 1
        }
        repeatRun = 0; acceptedBlocks += 1
        if block.acknowledged { acknowledgements += 1 }
        for code in words {
            switch code {
            case CCIR476.lettersShift: figures = false
            case CCIR476.figuresShift: figures = true
            case Self.beta, CCIR476.alpha, 0x6A: break
            default:
                guard let value = (figures ? CCIR476.figures : CCIR476.letters)[code] else { append("□"); continue }
                if value != 13 && value != 7 { append(String(UnicodeScalar(value))) }
            }
        }
    }

    func advance(to time: Double) {
        if let lastBlock, time - lastBlock.start > 1.4 { loseLock() }
    }
    func finish() { acquisition.removeAll(keepingCapacity: true) }
    private func loseLock() {
        if locked { resynchronizations += 1 }
        locked = false; acquisition.removeAll(keepingCapacity: true)
        lastBlock = nil; nextRequest = nil; figures = false; invalidRun = 0; repeatRun = 0
    }
    private func append(_ value: String) {
        text.append(value)
        if text.utf8.count > 65536 { text = String(text.suffix(32768)) }
    }
    var status: String {
        "\(locked ? "SITOR-A: cadencia 450 ms" : "Buscando ráfagas SITOR-A 210/450 ms") · \(acceptedBlocks) bloques 4/7 · \(invalidBlocks) ilegibles · \(acknowledgements) respuestas ACK observadas · \(retransmissions) retransmisiones omitidas · \(ambiguousDuplicates) duplicados sin confirmar. RX pasivo; 4/7 no es CRC y sin retorno no confirma entrega ARQ."
    }
}

final class SITORADecoder {
    private struct Point { let time: Double; let deviation: Double; let active: Bool }
    private var analytic: AnalyticAudio
    private let receiver = SITORABlockReceiver()
    private let center: Double, threshold: Double, inverted: Bool, smoothing: Double
    private var filteredFrequency = 0.0
    private var burstStart: Double?, lastActive = 0.0, lastTime = 0.0
    private var nextPointTime = 0.0
    private var points: [Point] = []
    private var overflow = false

    init(sampleRate: Double, settings: DecoderSettings) {
        analytic = AnalyticAudio(sampleRate: sampleRate)
        center = settings.frequency; threshold = settings.threshold; inverted = settings.inverted
        smoothing = 1 - exp(-1 / (sampleRate * 0.0007))
        points.reserveCapacity(600)
    }
    func process(_ samples: [Float]) {
        for sample in samples {
            guard let value = analytic.push(sample.isFinite ? sample : 0) else { continue }
            lastTime = value.time
            let active = value.amplitude >= threshold && value.frequency.isFinite && abs(value.frequency - center) < 190
            if active {
                filteredFrequency += smoothing * (value.frequency - center - filteredFrequency)
                if burstStart == nil {
                    burstStart = value.time; nextPointTime = value.time
                    points.removeAll(keepingCapacity: true); overflow = false
                }
                lastActive = value.time
            }
            guard let burstStart else { receiver.advance(to: value.time); continue }
            if value.time >= nextPointTime {
                if points.count < 600 { points.append(Point(time: value.time, deviation: filteredFrequency, active: active)) }
                else { overflow = true }
                nextPointTime = value.time + 0.0005
            }
            if value.time - burstStart > 0.280 { overflow = true }
            if value.time - lastActive >= 0.012 { completeBurst() }
        }
    }
    private func completeBurst() {
        guard let start = burstStart else { return }
        let duration = lastActive - start
        defer { burstStart = nil; points.removeAll(keepingCapacity: true); filteredFrequency = 0 }
        guard !overflow else { receiver.receive(words: [], start: start, duration: duration); return }
        let count = (0.058...0.082).contains(duration) ? 7 : (0.193...0.227).contains(duration) ? 21 : 0
        guard count > 0 else { receiver.receive(words: [], start: start, duration: duration); return }
        // Burst envelope uncertainty is bounded to a few milliseconds. Require
        // a unique valid word sequence over this small alignment search.
        var alternatives = Set<[UInt8]>()
        for offsetStep in -6...6 {
            let firstCenter = start + 0.005 + Double(offsetStep) * 0.0005
            var words: [UInt8] = [], word: UInt8 = 0
            var valid = true
            for bit in 0..<count {
                let time = firstCenter + Double(bit) * 0.010
                var sum = 0.0, votes = 0
                for point in points where abs(point.time - time) <= 0.002 && point.active {
                    sum += point.deviation; votes += 1
                }
                guard votes >= 3, abs(sum / Double(votes)) >= 20 else { valid = false; break }
                if (sum >= 0) != inverted { word |= 1 << (bit % 7) }
                if bit % 7 == 6 {
                    if !CCIR476.valid(word) { valid = false; break }
                    words.append(word); word = 0
                }
            }
            if valid { alternatives.insert(words) }
        }
        if alternatives.count == 1, let words = alternatives.first {
            receiver.receive(words: words.map(Optional.some), start: start, duration: duration)
        } else {
            receiver.receive(words: Array(repeating: nil, count: count / 7), start: start, duration: duration)
        }
    }
    func finish() { completeBurst(); receiver.advance(to: lastTime); receiver.finish() }
    var text: String { receiver.text }
    var status: String { receiver.status }
}
