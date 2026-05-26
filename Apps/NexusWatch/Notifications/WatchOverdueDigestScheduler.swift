import Foundation
import NexusCore
import SwiftData
import UserNotifications

protocol WatchIPhonePresenceProbing: AnyObject, Sendable {
    var lastIPhonePing: Date? { get }
}

/// Watch-side daily 09:00 overdue digest. Defers to the iPhone-mirrored digest
/// when the iPhone has been reachable since yesterday 21:00; otherwise fires
/// locally so the user is never left without a morning summary.
@MainActor
final class WatchOverdueDigestScheduler {
    static let identifier = "digest-overdue"

    private let context: ModelContext
    private let delivery: any NotificationDelivering
    private let presenceProbe: any WatchIPhonePresenceProbing
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    init(
        context: ModelContext,
        delivery: any NotificationDelivering,
        presenceProbe: any WatchIPhonePresenceProbing,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.delivery = delivery
        self.presenceProbe = presenceProbe
        self.calendar = calendar
        self.nowProvider = now
    }

    func refreshAndSchedule() async {
        await delivery.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let now = nowProvider()
        if shouldDeferToIPhone(now: now) { return }

        let count = overdueCount(now: now)
        let fireDate = nextNineAM(after: now)

        let content = UNMutableNotificationContent()
        content.title = "Zaległe zadania"
        content.body = "\(count) \(pluralisation(for: count))"
        content.categoryIdentifier = NotificationCategory.overdueDigest.rawValue

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: trigger
        )
        try? await delivery.add(request)
    }

    nonisolated private func shouldDeferToIPhone(now: Date) -> Bool {
        guard let lastPing = presenceProbe.lastIPhonePing else { return false }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayLate =
            calendar.date(
                bySettingHour: 21, minute: 0, second: 0, of: yesterday
            ) ?? yesterday
        return lastPing >= yesterdayLate
    }

    private func overdueCount(now: Date) -> Int {
        let openRaw = TaskStatus.open.rawValue
        let cutoff = calendar.startOfDay(for: now)
        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil
                    && task.statusRaw == openRaw
                    && task.dueAt != nil
                    && (task.dueAt ?? distantFuture) < cutoff
            }
        )
        return (try? context.fetch(descriptor).count) ?? 0
    }

    nonisolated private func nextNineAM(after date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let nineToday =
            calendar.date(
                bySettingHour: 9, minute: 0, second: 0, of: startOfDay
            ) ?? startOfDay
        if nineToday > date { return nineToday }
        return calendar.date(byAdding: .day, value: 1, to: nineToday) ?? nineToday
    }

    /// Inlined Polish three-form rule. Canonical helper is
    /// `PolishPlurals` in `TasksFeature` — duplicated here because the Watch
    /// target cannot depend on `TasksFeature` and uses the adjective-prefixed
    /// form ("zaległe / zaległych") that `PolishPlurals` does not expose.
    nonisolated private func pluralisation(for count: Int) -> String {
        let absoluteCount = abs(count)
        let lastTwoDigits = absoluteCount % 100
        let lastDigit = absoluteCount % 10

        if absoluteCount == 1 { return "zaległe zadanie" }
        if (2...4).contains(lastDigit), !(12...14).contains(lastTwoDigits) {
            return "zaległe zadania"
        }
        return "zaległych zadań"
    }
}
