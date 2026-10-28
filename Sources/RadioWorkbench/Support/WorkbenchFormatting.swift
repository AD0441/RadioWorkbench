import Foundation

/// Formatting belongs to the selected UI locale; external payloads stay verbatim.
enum WorkbenchFormatting {
    static func utcDay(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: locale, timeZone: TimeZone(secondsFromGMT: 0)!))
    }
    static func probability(_ value: Int?, locale: Locale) -> String {
        guard let value, (0...100).contains(value) else { return "—" }
        return (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
