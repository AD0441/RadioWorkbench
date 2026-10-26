import Foundation
import SwiftUI

/// Resolves only app-owned labels/statuses. Received payloads and user names stay verbatim.
@MainActor enum AppLocalization {
    private struct Pattern {
        let expression: NSRegularExpression
        let translated: String
        let prefix: String
    }
    static var resourceBundle: Bundle {
        Bundle.main.url(forResource: "Translations", withExtension: "json") != nil ? .main : .module
    }
    static let translations: [String: String] = {
        guard let url = resourceBundle.url(forResource: "Translations", withExtension: "json"), let data = try? Data(contentsOf: url), let table = try? JSONDecoder().decode([String:String].self, from: data) else { return [:] }
        return table
    }()
    private static let placeholder = try! NSRegularExpression(pattern: #"\{\d+\}"#)
    private static let printf = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:ll|l|z)?[diufgeG@]|%%"#)
    private static func normalized(_ value: String) -> String {
        var result = value
        let matches = printf.matches(in: value, range: NSRange(value.startIndex..., in: value))
        var number = 0
        var changes: [(Range<String.Index>, String)] = []
        for match in matches {
            guard let range = Range(match.range, in: value) else { continue }
            if value[range] == "%%" { changes.append((range, "%")) }
            else { changes.append((range, "{\(number)}")); number += 1 }
        }
        for (range, text) in changes.reversed() { result.replaceSubrange(range, with: text) }
        return result
    }
    private static let patterns: [Pattern] = translations.compactMap { sourceKey, sourceValue in
        let key = normalized(sourceKey), value = normalized(sourceValue)
        let matches = placeholder.matches(in: key, range: NSRange(key.startIndex..., in: key))
        guard !matches.isEmpty, key.replacingOccurrences(of: #"\{\d+\}"#, with: "", options: .regularExpression).count >= 5 else { return nil }
        var pattern = "^", offset = key.startIndex
        for match in matches {
            guard let range = Range(match.range, in: key) else { return nil }
            pattern += NSRegularExpression.escapedPattern(for: String(key[offset..<range.lowerBound])) + "([\\s\\S]*?)"
            offset = range.upperBound
        }
        pattern += NSRegularExpression.escapedPattern(for: String(key[offset...])) + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let first = matches.first.flatMap { Range($0.range,in:key) }?.lowerBound ?? key.endIndex
        return Pattern(expression: regex, translated: value, prefix: String(key[..<first]))
    }.sorted { $0.prefix.count > $1.prefix.count }
    private static var cache: [String:String] = [:]
    static func text(_ source: String, language: String? = nil) -> String {
        guard (language ?? AppPreferencesStore.shared.values.language) == "en" else { return source }
        if let exact = translations[source] { return exact }
        if let cached = cache[source] { return cached }
        for item in patterns {
            guard item.prefix.isEmpty || source.hasPrefix(item.prefix), let match = item.expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { continue }
            var answer = item.translated
            // Substitute only placeholders in the original template, from the end.
            // Captured user values containing braces are never scanned again.
            let slots = placeholder.matches(in: item.translated, range: NSRange(item.translated.startIndex..., in: item.translated))
            for slot in slots.reversed() {
                guard let range = Range(slot.range, in: item.translated),
                      let index = Int(item.translated[range].dropFirst().dropLast()), index + 1 < match.numberOfRanges,
                      let capture = Range(match.range(at: index + 1), in: source) else { continue }
                answer.replaceSubrange(range, with: String(source[capture]))
            }
            if cache.count >= 512 { cache.removeAll(keepingCapacity: true) }
            cache[source] = answer; return answer
        }
        return source
    }
}
