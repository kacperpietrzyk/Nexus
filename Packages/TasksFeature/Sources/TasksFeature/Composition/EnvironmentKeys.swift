import Foundation
import NexusCore
import SwiftUI

private struct TaskParserEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any NLParser)? = nil
}

private struct TaskRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: TaskItemRepository? = nil
}

private struct NotificationSchedulerKey: EnvironmentKey {
    static let defaultValue: NotificationScheduler? = nil
}

extension EnvironmentValues {
    /// Injected by app composition roots. Views access via
    /// `@Environment(\.taskParser)`.
    public var taskParser: (any NLParser)? {
        get { self[TaskParserEnvironmentKey.self] }
        set { self[TaskParserEnvironmentKey.self] = newValue }
    }

    /// Injected by app composition roots. `@MainActor`-bound because
    /// `TaskItemRepository` is `@MainActor`.
    public var taskRepository: TaskItemRepository? {
        get { self[TaskRepositoryEnvironmentKey.self] }
        set { self[TaskRepositoryEnvironmentKey.self] = newValue }
    }

    /// Injected by app composition roots. Views (e.g. `CustomSnoozeSheet`,
    /// notification action handlers) reach this for direct scheduling without
    /// going through the repository's fire-and-forget hooks.
    public var notificationScheduler: NotificationScheduler? {
        get { self[NotificationSchedulerKey.self] }
        set { self[NotificationSchedulerKey.self] = newValue }
    }
}
