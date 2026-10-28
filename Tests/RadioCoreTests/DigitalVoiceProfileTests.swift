import Foundation
import Testing
@testable import RadioCore
@testable import RadioWorkbench

@Test func digitalVoicePresetsDistinguishActualChannelWidthFromTDMASlots() {
    // DMR and P25 II retain the whole RF channel even when listening to one slot.
    #expect(DigitalVoiceProtocol.dmr.receptionPreset.rfBandwidthHz == 12500)
    #expect(DigitalVoiceProtocol.p25p2.receptionPreset.rfBandwidthHz == 12500)
    #expect(DigitalVoiceProtocol.nxdn48.receptionPreset.rfBandwidthHz == 6250)
    #expect(DigitalVoiceProtocol.nxdn96.receptionPreset.rfBandwidthHz == 12500)
    #expect(DigitalVoiceProtocol.dpmr.receptionPreset.rfBandwidthHz == 6250)
    #expect(DigitalVoiceProtocol.dstar.receptionPreset.rfBandwidthHz == 6250)
    for kind in DigitalVoiceProtocol.allCases {
        let preset = kind.receptionPreset
        #expect(preset.sampleRate == RadioMode.digitalVoice.engineSampleRate && preset.channels == 1)
        #expect(preset.modulation == .fm && preset.sourceURL.scheme == "https")
        #expect(!preset.signalModulation.isEmpty && !preset.note.isEmpty)
    }
}

@MainActor @Test func digitalVoicePresetRequiresExplicitApplicationAndPreservesTransport() {
    let receiver = ReceiverStore()
    receiver.select(.digitalVoice)
    receiver.rfBandwidth = 14000
    receiver.settings.frequency = 1730
    receiver.settings.dmrSlotSelection = .ts2
    receiver.settings.dmrMonitorVoice = true
    receiver.settings.audioChannel = .channel(1)
    receiver.networkPCM.channels = 2
    receiver.networkPCM.sampleRate = 96000
    receiver.settings.digitalVoiceProtocol = .nxdn48
    #expect(receiver.rfBandwidth == 14000) // Changing the protocol alone does not apply a setup.
    receiver.applyDigitalVoicePreset()
    #expect(receiver.rfModulation == .fm && receiver.rfBandwidth == 6250)
    #expect(receiver.settings.digitalVoiceProtocol == .nxdn48 && receiver.settings.frequency == 1730)
    #expect(receiver.settings.audioChannel == .channel(1))
    #expect(receiver.settings.dmrSlotSelection == .ts2 && receiver.settings.dmrMonitorVoice)
    #expect(receiver.networkPCM.channels == 2 && receiver.networkPCM.sampleRate == 96000)
    #expect(!receiver.busy && !receiver.live)
    receiver.busy = true
    receiver.settings.digitalVoiceProtocol = .dmr
    receiver.applyDigitalVoicePreset()
    #expect(receiver.rfBandwidth == 6250) // A running session cannot change its guide accidentally.
    receiver.busy = false
    receiver.stop()
}
