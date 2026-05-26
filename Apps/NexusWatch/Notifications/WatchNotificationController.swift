import Foundation
import SwiftUI
import UserNotifications
import WatchKit

final class WatchNotificationController: WKUserNotificationHostingController<WatchNotificationView> {
    private var receivedTitle: String = ""
    private var receivedDueAt: Date = .distantFuture
    private var receivedProjectName: String?

    override var body: WatchNotificationView {
        WatchNotificationView(
            title: receivedTitle,
            dueAt: receivedDueAt,
            projectName: receivedProjectName
        )
    }

    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        receivedTitle = content.title
        receivedProjectName = content.subtitle.isEmpty ? nil : content.subtitle
        if let dueRaw = content.userInfo["dueAt"] as? TimeInterval {
            receivedDueAt = Date(timeIntervalSince1970: dueRaw)
        } else {
            receivedDueAt =
                (notification.request.trigger as? UNCalendarNotificationTrigger)?
                .nextTriggerDate() ?? Date()
        }
    }
}
