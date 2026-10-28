import SwiftUI
import AppKit

enum AppPalette: String, CaseIterable, Identifiable, Codable {
    case graphite, petroleum, forest, amber
    var id: String { rawValue }
    var title: String {
        switch self { case .graphite: "Grafito"; case .petroleum: "Petróleo"; case .forest: "Bosque"; case .amber: "Ámbar" }
    }
    /// Semantic surfaces and warning colors remain managed by macOS.
    @MainActor var color: Color {
        let light: (Double, Double, Double), dark: (Double, Double, Double)
        switch self {
        case .graphite: light = (0.29,0.29,0.29); dark = (0.84,0.84,0.84)
        case .petroleum: light = (0,0.42,0.44); dark = (0.40,0.84,0.83)
        case .forest: light = (0.18,0.42,0.27); dark = (0.53,0.82,0.64)
        case .amber: light = (0.53,0.36,0); dark = (0.91,0.75,0.40)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
