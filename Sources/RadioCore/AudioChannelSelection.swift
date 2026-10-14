import Foundation

public enum AudioChannelSelection: Hashable, Codable, Sendable {
    case mix
    case channel(Int)
    public var label: String {
        switch self {
        case .mix: "Mezclar canales"
        case .channel(0): "Canal 1 · L"
        case .channel(1): "Canal 2 · R"
        case .channel(let index): "Canal \(index + 1)"
        }
    }
    public func validate(channelCount: Int) throws {
        guard channelCount > 0 else { throw RadioError.invalidAudio }
        if case .channel(let index) = self, index < 0 || index >= channelCount {
            throw RadioError.unavailableAudioChannel(index: index, available: channelCount)
        }
    }
}
