import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let sampleRate: Double
    let channels: Int
    let uid: String
    let isBuiltIn: Bool
}

enum AudioInputDevices {
    static func defaultID() -> UInt32 {
        uintProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) ?? 0
    }

    static func list() -> [AudioInputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var property = address(kAudioHardwarePropertyDevices)
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &byteCount) == noErr,
              byteCount >= MemoryLayout<AudioDeviceID>.size else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &property, 0, nil, &byteCount, $0.baseAddress!)
        }
        guard status == noErr else { return [] }
        let currentDefault = defaultID()
        return ids.prefix(Int(byteCount) / MemoryLayout<AudioDeviceID>.size).compactMap { id in
            guard id != 0,
                  uintProperty(id, kAudioDevicePropertyDeviceIsAlive) == 1 else { return nil }
            let channels = inputChannelCount(id)
            guard channels > 0,
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? "Entrada de audio"
            // Engine-owned transient aggregates are not independent user inputs.
            guard !name.hasPrefix("CADefaultDeviceAggregate-") else { return nil }
            return AudioInputDevice(id: id,
                                    name: name,
                                    sampleRate: nominalSampleRate(id),
                                    channels: channels,
                                    uid: uid,
                                    isBuiltIn: uintProperty(id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn)
        }.sorted { lhs, rhs in
            if (lhs.id == currentDefault) != (rhs.id == currentDefault) { return lhs.id == currentDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func uintProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var property = address(selector)
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &property, 0, nil, &byteCount, &value) == noErr ? value : nil
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &byteCount, &value) == noErr,
              let value else { return nil }
        // HAL returns retained CFObjects for these two string properties.
        return value.takeRetainedValue() as String
    }

    private static func nominalSampleRate(_ device: AudioDeviceID) -> Double {
        var property = address(kAudioDevicePropertyNominalSampleRate)
        var value: Float64 = 0
        var byteCount = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(device, &property, 0, nil, &byteCount, &value) == noErr ? value : 0
    }

    private static func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &byteCount) == noErr,
              byteCount >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(byteCount), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &byteCount, storage) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
