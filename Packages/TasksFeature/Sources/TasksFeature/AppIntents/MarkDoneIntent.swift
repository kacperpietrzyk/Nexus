#if canImport(AppIntents)
import AppIntents

public struct MarkDoneIntent: AppIntent {
    public static let title: LocalizedStringResource = "Mark Task Done"
    public static let description = IntentDescription("Marks a Nexus task as done.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Task")
    public var task: TaskAppEntity

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await TaskIntentRuntime.shared.markDone(task)
        return .result(dialog: "Marked \(task.title) done.")
    }
}
#endif
