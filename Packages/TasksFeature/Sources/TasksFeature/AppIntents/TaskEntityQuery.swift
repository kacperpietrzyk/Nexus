#if canImport(AppIntents)
import AppIntents

/// Background-safe `EntityStringQuery` that hops to MainActor to read SwiftData
/// through `TaskIntentRuntime.shared`. Same pattern as
/// `NotificationScheduler` — non-`Sendable` `TaskItem` stays isolated.
public struct TaskEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [TaskAppEntity] {
        try await TaskIntentRuntime.shared.entities(for: identifiers)
    }

    public func entities(matching string: String) async throws -> [TaskAppEntity] {
        try await TaskIntentRuntime.shared.entities(matching: string)
    }

    public func suggestedEntities() async throws -> [TaskAppEntity] {
        try await TaskIntentRuntime.shared.entities(matching: "")
    }
}
#endif
