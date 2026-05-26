#if canImport(AppIntents)
import AppIntents

public struct AddTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Task"
    public static let description = IntentDescription("Adds a task to Nexus from natural language.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Task description")
    public var input: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<TaskAppEntity> & ProvidesDialog {
        let entity = try await TaskIntentRuntime.shared.addTask(input: input)
        return .result(value: entity, dialog: "Added \(entity.title).")
    }
}
#endif
