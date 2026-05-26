import Foundation
import NexusCore
import OSLog
import SwiftData
import UserNotifications

private struct NotificationCompletionHandler: @unchecked Sendable {
    let complete: () -> Void

    func call() {
        complete()
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
public final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus",
        category: "NotificationActionHandler"
    )

    private let repository: TaskItemRepository
    private let scheduler: NotificationScheduler
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        repository: TaskItemRepository,
        scheduler: NotificationScheduler,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
        super.init()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let idString = response.notification.request.content.userInfo["taskId"] as? String
        let actionID = response.actionIdentifier
        let completion = NotificationCompletionHandler(complete: completionHandler)
        if let idString, let id = UUID(uuidString: idString) {
            Task { @MainActor in
                handleAction(actionID, taskID: id)
                completion.call()
            }
        } else {
            completion.call()
        }
    }

    private func handleAction(_ actionID: String, taskID id: UUID) {
        switch actionID {
        case NotificationActionID.snooze15M.rawValue:
            performSnooze(taskID: id, by: 15 * 60)
        case NotificationActionID.snooze1H.rawValue:
            performSnooze(taskID: id, by: 60 * 60)
        case NotificationActionID.snoozeTomorrow.rawValue:
            performSnooze(taskID: id, until: nextMorningNine(after: now()))
        case NotificationActionID.snoozeCustom.rawValue:
            openCustomSnoozeURL(for: id)
        default:
            break
        }
    }

    private func performSnooze(taskID: UUID, by interval: TimeInterval) {
        performSnooze(taskID: taskID, until: now().addingTimeInterval(interval))
    }

    private func performSnooze(taskID: UUID, until: Date) {
        guard let task = fetchTask(id: taskID) else { return }
        do {
            try repository.snooze(task, until: until)
            Task { @MainActor [scheduler] in
                do {
                    try await scheduler.scheduleSnooze(task, until: until)
                } catch {
                    Self.logger.error(
                        "scheduleSnooze failed for taskID \(taskID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        } catch {
            Self.logger.error(
                "snooze failed for taskID \(taskID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func openCustomSnoozeURL(for id: UUID) {
        guard let url = URL(string: "nexus://task/\(id.uuidString)/snooze") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func fetchTask(id: UUID) -> TaskItem? {
        let predicate = #Predicate<TaskItem> { $0.id == id }
        let descriptor = FetchDescriptor<TaskItem>(predicate: predicate)
        return try? repository.context.fetch(descriptor).first
    }

    private func nextMorningNine(after date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
