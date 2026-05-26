#if canImport(AppIntents)
import AppIntents

public struct TaskShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add task in \(.applicationName)",
                "Capture task in \(.applicationName)",
                "New task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: MarkDoneIntent(),
            phrases: [
                "Mark task done in \(.applicationName)",
                "Complete task in \(.applicationName)",
            ],
            shortTitle: "Mark Done",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: SnoozeTaskIntent(),
            phrases: [
                "Snooze task in \(.applicationName)",
                "Defer task in \(.applicationName)",
            ],
            shortTitle: "Snooze Task",
            systemImageName: "clock"
        )
    }
}
#endif
