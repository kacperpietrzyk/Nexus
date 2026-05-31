import AppIntents
import Foundation

struct WatchAddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Sends a task capture to the paired device.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Task description")
    var input: String

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Tell me what to add.")
        }
        try await WatchPhoneBridge.sendCaptureToPhone(input: trimmed)
        return .result(dialog: "Sent to Nexus.")
    }
}

struct WatchTaskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchAddTaskIntent(),
            phrases: [
                "Add task in \(.applicationName)",
                "Add a task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: AskNexusIntent(),
            phrases: [
                "Ask Nexus in \(.applicationName)"
            ],
            shortTitle: "Ask Nexus",
            systemImageName: "sparkles"
        )
    }
}
