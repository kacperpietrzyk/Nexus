#if canImport(AppIntents)
import AppIntents

public struct TaskShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add task in \(.applicationName)",
                "Dodaj task w \(.applicationName)",
                "Capture task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: MarkDoneIntent(),
            phrases: [
                "Mark task done in \(.applicationName)",
                "Oznacz task jako zrobiony w \(.applicationName)",
            ],
            shortTitle: "Mark Done",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: SnoozeTaskIntent(),
            phrases: [
                "Snooze task in \(.applicationName)",
                "Odłóż task w \(.applicationName)",
            ],
            shortTitle: "Snooze Task",
            systemImageName: "clock"
        )
    }
}
#endif
