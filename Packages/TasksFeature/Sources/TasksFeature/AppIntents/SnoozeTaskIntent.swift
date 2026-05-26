#if canImport(AppIntents)
import AppIntents
import Foundation

public struct SnoozeTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Snooze Task"
    public static let description = IntentDescription("Snoozes a Nexus task until a selected date.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Task")
    public var task: TaskAppEntity

    @Parameter(title: "Until")
    public var until: Date

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TaskIntentRuntime.shared.snooze(task, until: until)
        return .result(dialog: "Snoozed \(task.title).")
    }
}
#endif
