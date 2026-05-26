import NexusCore
import NexusSync
import SwiftData
import UIKit
import UserNotifications
import UserNotificationsUI

/// UNNotificationContentExtension for the daily overdue-digest notification
/// (category `OVERDUE_DIGEST`). Queries the App Group SwiftData store at
/// delivery time so the body reflects live overdue counts, regardless of
/// when the notification was scheduled.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
    }

    func didReceive(_ notification: UNNotification) {
        let counts = countOverdue()
        if counts.titles.isEmpty {
            titleLabel.text = "No overdue tasks"
            bodyLabel.text = ""
            return
        }
        titleLabel.text = "\(counts.count) overdue tasks"
        let firstThree = counts.titles.prefix(3).joined(separator: "\n• ")
        bodyLabel.text = firstThree.isEmpty ? "" : "• \(firstThree)"
    }

    private struct OverdueCounts {
        let count: Int
        let titles: [String]
    }

    /// Stub `NexusEnvironmentProviding` so the extension can construct the
    /// shared container without tripping the CloudKit path. The main app
    /// owns CloudKit sync; the extension only reads the local mirror.
    private struct ExtensionEnvironment: NexusEnvironmentProviding {
        var cloudKitEnabled: Bool { false }
        var cloudKitContainerIdentifier: String { NexusEnvironment.containerIdentifier }
    }

    @MainActor
    private func countOverdue() -> OverdueCounts {
        do {
            let container = try NexusModelContainer.make(
                environment: ExtensionEnvironment(),
                groupContainerIdentifier: "group.com.kacperpietrzyk.Nexus"
            )
            let context = ModelContext(container)
            let now = Date.now
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.statusRaw == "open"
                        && task.deletedAt == nil
                        && task.dueAt != nil
                },
                sortBy: [SortDescriptor(\.dueAt)]
            )
            let all = try context.fetch(descriptor)
            let startOfDay = Calendar.current.startOfDay(for: now)
            let overdue = all.filter { task in
                guard let due = task.dueAt else { return false }
                return due < startOfDay
            }
            return OverdueCounts(count: overdue.count, titles: overdue.map(\.title))
        } catch {
            return OverdueCounts(count: 0, titles: [])
        }
    }
}
