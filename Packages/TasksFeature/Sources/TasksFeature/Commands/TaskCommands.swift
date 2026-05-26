import CommandPaletteShell
import Foundation
import NexusCore

@MainActor
public struct TaskCommandNavigation {
    public let goToToday: @MainActor @Sendable () -> Void
    public let goToInbox: @MainActor @Sendable () -> Void
    public let openCapture: @MainActor @Sendable () -> Void
    public let selectedTask: @MainActor @Sendable () -> TaskItem?

    public init(
        goToToday: @escaping @MainActor @Sendable () -> Void,
        goToInbox: @escaping @MainActor @Sendable () -> Void,
        openCapture: @escaping @MainActor @Sendable () -> Void,
        selectedTask: @escaping @MainActor @Sendable () -> TaskItem?
    ) {
        self.goToToday = goToToday
        self.goToInbox = goToInbox
        self.openCapture = openCapture
        self.selectedTask = selectedTask
    }
}

public final class AddTaskCommand: Command, @unchecked Sendable {
    public let id = "tasks.add"
    public let title = "Add Task"
    public let subtitle: String? = "Open capture"
    public let iconName = "plus.circle"
    public let keywords = ["new", "capture", "quick add", "task"]
    public let shortcut = ["⌘", "⌃", "N"]
    private let openCapture: @MainActor @Sendable () -> Void

    public init(openCapture: @escaping @MainActor @Sendable () -> Void) {
        self.openCapture = openCapture
    }

    public func execute() async throws {
        await MainActor.run { openCapture() }
    }
}

public final class MarkSelectedDoneCommand: Command, @unchecked Sendable {
    public let id = "tasks.mark-selected-done"
    public let title = "Mark Selected Done"
    public let subtitle: String? = "Complete the current task"
    public let iconName = "checkmark.circle"
    public let keywords = ["done", "complete", "finish"]
    public let shortcut: [String] = []
    private let repository: TaskItemRepository
    private let selectedTask: @MainActor @Sendable () -> TaskItem?

    public init(repository: TaskItemRepository, selectedTask: @escaping @MainActor @Sendable () -> TaskItem?) {
        self.repository = repository
        self.selectedTask = selectedTask
    }

    public var availability: CommandAvailability {
        get async {
            await MainActor.run {
                guard let task = selectedTask() else {
                    return .disabled(reason: "Select a task first")
                }
                guard task.status != .done else {
                    return .disabled(reason: "Task is already done")
                }
                return .enabled
            }
        }
    }

    public func execute() async throws {
        try await MainActor.run {
            guard let task = selectedTask(), task.status != .done else { return }
            try TaskCompletionAction.completeOrCascade(task, repository: repository)
        }
    }
}

public final class SnoozeSelectedCommand: Command, @unchecked Sendable {
    public let id = "tasks.snooze-selected"
    public let title = "Snooze Selected 1 Hour"
    public let subtitle: String? = "Move the current task out of the way"
    public let iconName = "clock"
    public let keywords = ["delay", "later", "snooze"]
    public let shortcut: [String] = []
    private let repository: TaskItemRepository
    private let selectedTask: @MainActor @Sendable () -> TaskItem?

    public init(repository: TaskItemRepository, selectedTask: @escaping @MainActor @Sendable () -> TaskItem?) {
        self.repository = repository
        self.selectedTask = selectedTask
    }

    public var availability: CommandAvailability {
        get async {
            await MainActor.run {
                guard selectedTask() != nil else {
                    return .disabled(reason: "Select a task first")
                }
                return .enabled
            }
        }
    }

    public func execute() async throws {
        try await MainActor.run {
            guard let task = selectedTask() else { return }
            try repository.snooze(task, until: repository.now().addingTimeInterval(3600))
        }
    }
}

public final class ToggleFocusCommand: Command, @unchecked Sendable {
    public let id = "tasks.toggle-focus"
    public let title = "Toggle Focus"
    public let subtitle: String? = "Pin or unpin the current task"
    public let iconName = "scope"
    public let keywords = ["focus", "pin"]
    public let shortcut: [String] = []
    private let repository: TaskItemRepository
    private let selectedTask: @MainActor @Sendable () -> TaskItem?

    public init(repository: TaskItemRepository, selectedTask: @escaping @MainActor @Sendable () -> TaskItem?) {
        self.repository = repository
        self.selectedTask = selectedTask
    }

    public var availability: CommandAvailability {
        get async {
            await MainActor.run {
                guard selectedTask() != nil else {
                    return .disabled(reason: "Select a task first")
                }
                return .enabled
            }
        }
    }

    public func execute() async throws {
        try await MainActor.run {
            guard let task = selectedTask() else { return }
            try repository.update(task) { $0.pinnedAsFocus.toggle() }
        }
    }
}

public final class GoToTodayCommand: Command, @unchecked Sendable {
    public let id = "tasks.go-today"
    public let title = "Go to Today"
    public let subtitle: String? = "Open Today's task view"
    public let iconName = "sun.max.fill"
    public let keywords = ["today", "home"]
    public let shortcut = ["⌘", "1"]
    private let action: @MainActor @Sendable () -> Void

    public init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    public func execute() async throws {
        await MainActor.run { action() }
    }
}

public final class GoToInboxCommand: Command, @unchecked Sendable {
    public let id = "tasks.go-inbox"
    public let title = "Go to Inbox"
    public let subtitle: String? = "Open unsorted and snoozed tasks"
    public let iconName = "tray"
    public let keywords = ["inbox", "unsorted", "snoozed"]
    public let shortcut = ["⌘", "2"]
    private let action: @MainActor @Sendable () -> Void

    public init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    public func execute() async throws {
        await MainActor.run { action() }
    }
}
