import Foundation
import Testing
@testable import RadioCore

// Literal emitted B/Y strings from ITU-R M.476-5 Tables 1 and 2. The
// reference waveform generator does not read the receiver's lookup tables.
private let sitorAWire: [String: String] = [
    "T": "YYBYBBB", "E": "YBBYBYB", "S": "BBYBYYB", "I": "BYBBYYB",
    "O": "BYYYBBB", "R": "BYBYBYB", "A": "BBBYYYB", " ": "YYBBBYB",
    "Q": "YBBBYBY", "W": "BBBYYBY", "N": "BYYBBYB", "\n": "YYBBYBB",
    "F": "YBBYBBY", "L": "YBYBBYB", "CS1": "BYBYYBB", "CS2": "YBYBYBB"
]
private func aCode(_ name: String) -> UInt8 {
    sitorAWire[name]!.enumerated().reduce(UInt8(0)) { $0 | ($1.element == "B" ? 1 << $1.offset : 0) }
}
private let aMessage = [["T", "E", "S"], ["T", " ", "S"], ["I", "T", "O"],
                        ["R", " ", "A"], ["F", "Q", "W"], ["E", "L", "\n"]]

@Test func sitorARequiresThreeTimedBlocksNotConstantWeightStream() {
    let receiver = SITORABlockReceiver()
    for (index, block) in aMessage.enumerated() {
        receiver.receive(words: block.map { aCode($0) }, start: Double(index) * 0.210, duration: 0.210)
    }
    #expect(receiver.text.isEmpty)
    #expect(!receiver.locked)
    let second = SITORABlockReceiver()
    second.receive(words: aMessage[0].map { aCode($0) }, start: 0, duration: 0.210)
    second.receive(words: aMessage[1].map { aCode($0) }, start: 0.450, duration: 0.210)
    #expect(second.text.isEmpty)
    second.receive(words: aMessage[2].map { aCode($0) }, start: 0.900, duration: 0.210)
    #expect(second.text == "TEST SITO")
    #expect(second.locked)
}

@Test func sitorAControlsAndProvenRetransmissionPreserveLettersAndFigures() {
    let receiver = SITORABlockReceiver()
    receiver.receive(words: [aCode("CS1")], start: 0.1, duration: 0.070)
    var time = 0.5
    for (index, block) in aMessage.enumerated() {
        let request = index % 2 == 0 ? "CS1" : "CS2"
        if index == 2 {
            receiver.receive(words: block.map { aCode($0) }, start: time, duration: 0.210)
            receiver.receive(words: [aCode(request)], start: time + 0.290, duration: 0.070)
            time += 0.450
        }
        receiver.receive(words: block.map { aCode($0) }, start: time, duration: 0.210)
        receiver.receive(words: [aCode(request == "CS1" ? "CS2" : "CS1")], start: time + 0.290, duration: 0.070)
        time += 0.450
    }
    #expect(receiver.text == "TEST SITOR A123\n")
    #expect(receiver.retransmissions == 1)
    #expect(receiver.acknowledgements == 6)
    #expect(receiver.invalidBlocks == 0)
}

@Test func sitorANoReturnPreservesAmbiguousEqualBlocksAndDoesNotClaimACK() {
    let receiver = SITORABlockReceiver()
    for index in 0..<4 {
        receiver.receive(words: [aCode("A"), aCode("A"), aCode("A")], start: Double(index) * 0.450, duration: 0.210)
    }
    #expect(receiver.text == String(repeating: "A", count: 12))
    #expect(receiver.acknowledgements == 0)
    #expect(receiver.retransmissions == 0)
    #expect(receiver.ambiguousDuplicates == 3)
}

@Test func sitorARejectsMutilatedBlocksAndReacquiresAfterSilence() {
    let receiver = SITORABlockReceiver()
    for index in 0..<3 { receiver.receive(words: aMessage[index].map { aCode($0) }, start: Double(index) * 0.450, duration: 0.210) }
    receiver.receive(words: [aCode("R"), 0, aCode("A")], start: 1.350, duration: 0.210)
    #expect(receiver.invalidBlocks == 1)
    #expect(receiver.text == "TEST SITO�")
    receiver.advance(to: 4)
    #expect(!receiver.locked)
    for index in 0..<3 { receiver.receive(words: aMessage[index].map { aCode($0) }, start: 4 + Double(index) * 0.450, duration: 0.210) }
    #expect(receiver.text == "TEST SITO�TEST SITO")
    #expect(receiver.resynchronizations == 1)
}

@Test func sitorAControlCodesInDataAreLettersAndSingleControlsNeverProduceText() {
    let receiver = SITORABlockReceiver()
    for index in 0..<3 { receiver.receive(words: [aCode("CS1"), aCode("N"), aCode("A")], start: Double(index) * 0.450, duration: 0.210) }
    #expect(receiver.text == "LNALNALNA")
    let onlyControl = SITORABlockReceiver()
    for index in 0..<12 { onlyControl.receive(words: [aCode(index % 2 == 0 ? "CS1" : "CS2")], start: Double(index) * 0.450, duration: 0.070) }
    #expect(onlyControl.text.isEmpty)
    #expect(!onlyControl.locked)
}

private struct AToneBurst { let symbols: [String]; let time: Double }
private func aAudio(rate: Double, inverted: Bool, repeats: Bool, returnChannel: Bool = true) -> [Float] {
    var bursts: [AToneBurst] = returnChannel ? [.init(symbols: ["CS1"], time: 0.2)] : []
    var time = 0.5
    for (index, block) in aMessage.enumerated() {
        let request = index % 2 == 0 ? "CS1" : "CS2"
        if repeats && index == 2 {
            bursts.append(.init(symbols: block, time: time))
            if returnChannel { bursts.append(.init(symbols: [request], time: time + 0.290)) }
            time += 0.450
        }
        bursts.append(.init(symbols: block, time: time))
        if returnChannel { bursts.append(.init(symbols: [request == "CS1" ? "CS2" : "CS1"], time: time + 0.290)) }
        time += 0.450
    }
    var audio = [Float](repeating: 0, count: Int((time + 0.5) * rate))
    for burst in bursts {
        let bits = burst.symbols.flatMap { Array(sitorAWire[$0]!) }
        var phase = 0.731
        for (index, bit) in bits.enumerated() {
            let frequency = ((bit == "B") != inverted) ? 1785.0 : 1615.0
            let start = Int(((burst.time + Double(index) / 100) * rate).rounded())
            let end = Int(((burst.time + Double(index + 1) / 100) * rate).rounded())
            for sample in start..<end {
                audio[sample] = Float(0.58 * sin(phase + 2 * .pi * frequency * Double(sample - start) / rate))
            }
            phase = (phase + 2 * .pi * frequency * Double(end - start) / rate).truncatingRemainder(dividingBy: 2 * .pi)
        }
    }
    return audio
}

@Test(arguments: [8000.0, 12000.0, 44100.0, 48000.0])
func sitorAAudioFramingSurvivesFragmentedBuffers(_ rate: Double) {
    var settings = DecoderSettings(); settings.frequency = 1700
    let decoder = SITORADecoder(sampleRate: rate, settings: settings)
    let audio = aAudio(rate: rate, inverted: false, repeats: true)
    for offset in stride(from: 0, to: audio.count, by: 317) { decoder.process(Array(audio[offset..<min(offset + 317, audio.count)])) }
    decoder.finish()
    #expect(decoder.text == "TEST SITOR A123\n")
    #expect(decoder.status.contains("1 retransmisiones omitidas"))
}

@Test func sitorAAudioInversionAndOneWayReturnUnknown() {
    var settings = DecoderSettings(); settings.frequency = 1700; settings.inverted = true
    let decoder = SITORADecoder(sampleRate: 8000, settings: settings)
    decoder.process(aAudio(rate: 8000, inverted: true, repeats: false, returnChannel: false)); decoder.finish()
    #expect(decoder.text == "TEST SITOR A123\n")
    #expect(decoder.status.contains("0 respuestas ACK observadas"))
}

@Test func sitorASilenceSteadyTonesAndContinuousCCIRNeverBecomeMessages() {
    var settings = DecoderSettings(); settings.frequency = 1700
    let decoder = SITORADecoder(sampleRate: 8000, settings: settings)
    decoder.process([Float](repeating: 0, count: 8000))
    decoder.process((0..<24000).map { Float(0.5 * sin(2 * .pi * 1785 * Double($0) / 8000)) })
    let burstAudio = aAudio(rate: 8000, inverted: false, repeats: false, returnChannel: false)
    var continuous: [Float] = []
    for index in 0..<aMessage.count {
        let start = Int(((0.5 + Double(index) * 0.450) * 8000).rounded())
        continuous.append(contentsOf: burstAudio[start..<(start + 1680)])
    }
    decoder.process(continuous)
    decoder.process([Float](repeating: 0, count: 8000)); decoder.finish()
    #expect(decoder.text.isEmpty)
}

@Test func sitorAAudioNoiseAndInvalidSamplesRemainBounded() {
    var settings = DecoderSettings(); settings.frequency = 1700
    let decoder = SITORADecoder(sampleRate: 8000, settings: settings)
    var audio = aAudio(rate: 8000, inverted: false, repeats: false)
    var random: UInt64 = 476_100
    for index in audio.indices {
        var gaussian = 0.0
        for _ in 0..<12 {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            gaussian += Double(random >> 32) / Double(UInt32.max)
        }
        audio[index] += Float((gaussian - 6) * 0.025)
    }
    decoder.process([.nan, .infinity, -.infinity]); decoder.process(audio); decoder.finish()
    #expect(decoder.text == "TEST SITOR A123\n")
}

@Test func sitorAEndAndChangeoverServiceBlocksNeverLeakIntoText() {
    for ending in [[UInt8](repeating: CCIR476.alpha, count: 3), [SITORABlockReceiver.beta, CCIR476.alpha, SITORABlockReceiver.beta]] {
        let receiver = SITORABlockReceiver()
        for index in 0..<3 { receiver.receive(words: aMessage[index].map { aCode($0) }, start: Double(index) * 0.450, duration: 0.210) }
        receiver.receive(words: ending.map(Optional.some), start: 1.350, duration: 0.210)
        #expect(receiver.text == "TEST SITO")
        #expect(!receiver.locked)
        let duringAcquisition = SITORABlockReceiver()
        duringAcquisition.receive(words: ending.map(Optional.some), start: 0, duration: 0.210)
        duringAcquisition.receive(words: aMessage[0].map { aCode($0) }, start: 0.450, duration: 0.210)
        duringAcquisition.receive(words: aMessage[1].map { aCode($0) }, start: 0.900, duration: 0.210)
        #expect(duringAcquisition.text.isEmpty)
        #expect(!duringAcquisition.locked)
    }
}
