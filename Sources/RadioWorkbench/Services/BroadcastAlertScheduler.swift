import Foundation
import RadioCore
import UserNotifications

@MainActor final class BroadcastAlertScheduler {
    private lazy var center = UNUserNotificationCenter.current()
    private let prefix = "broadcast-favorite-"

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(entries: [BroadcastEntry], leadMinutes: Int, now: Date = Date()) async throws -> Int {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        let lead = TimeInterval(min(max(0, leadMinutes), 60) * 60)
        let events = entries.compactMap { entry -> (BroadcastEntry, Date)? in
            guard let start = BroadcastCalendar.nextScheduledStart(entry, after: now.addingTimeInterval(lead), daysAhead: 14) else { return nil }
            return (entry, start.addingTimeInterval(-lead))
        }.sorted { $0.1 < $1.1 }.prefix(60)
        for (entry, fireDate) in events {
            let content = UNMutableNotificationContent()
            content.title = "Emisión favorita próxima"
            content.body = "\(entry.station) · \(entry.frequencyKHz.formatted(.number.precision(.fractionLength(0...2)))) kHz · inicio \(entry.time.prefix(4)) UTC"
            content.sound = .default
            content.userInfo = ["entryID": entry.id]
            var calendar = BroadcastCalendar.utc
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + entry.id, content: content, trigger: trigger)
            try await center.add(request)
        }
        return events.count
    }
}
