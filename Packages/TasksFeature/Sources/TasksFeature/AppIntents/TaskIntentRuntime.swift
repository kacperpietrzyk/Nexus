#if canImport(AppIntents)
import Foundation
import NexusCore
import SwiftData

/// Background-safe singleton that App Intents reach into to resolve the same
/// parser and repository the running app uses. App Intents can fire from a
/// suspended process, before any `ContentView` exists, so the host apps wire
/// this in their `init()` rather than in a `.task` modifier.
@MainActor
public final class TaskIntentRuntime {
    public static let shared = TaskIntentRuntime()

    private var parser: (any NLParser)?
    private var repository: TaskItemRepository?

    private init() {}

    public static func configure(parser: any NLParser, repository: TaskItemRepository) {
        shared.parser = parser
        shared.repository = repository
    }

    public func addTask(input: String) async throws -> TaskAppEntity {
        guard let parser, let repository else { throw TaskIntentRuntimeError.notConfigured }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskIntentRuntimeError.emptyInput }
        let result = await parser.parse(trimmed, locale: .current, now: Date())
        let projectID = result.projectToken.flatMap { token in
            (try? ProjectRepository(context: repository.context)
                .findActive(matchingToken: token))
                .flatMap { $0 }?.id
        }
        let task = TaskItem(
            title: result.title,
            dueAt: result.dueAt,
            startAt: result.startAt,
            endAt: result.endAt,
            deadlineAt: result.deadlineAt,
            priority: result.priority ?? .none,
            tags: result.tags,
            recurrenceRule: result.recurrence,
            projectID: projectID
        )
        try repository.insert(task)
        return TaskAppEntity(task: task)
    }

    public func markDone(_ entity: TaskAppEntity) async throws {
        guard let repository else { throw TaskIntentRuntimeError.notConfigured }
        guard let task = try find(entity.id, repository: repository) else {
            throw TaskIntentRuntimeError.taskNotFound
        }
        try TaskCompletionAction.completeOrCascade(task, repository: repository)
    }

    public func snooze(_ entity: TaskAppEntity, until date: Date) async throws {
        guard let repository else { throw TaskIntentRuntimeError.notConfigured }
        guard let task = try find(entity.id, repository: repository) else {
            throw TaskIntentRuntimeError.taskNotFound
        }
        try repository.snooze(task, until: date)
    }

    public func entities(for identifiers: [String]) throws -> [TaskAppEntity] {
        guard let repository else { throw TaskIntentRuntimeError.notConfigured }
        let ids = identifiers.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                ids.contains(task.id) && task.deletedAt == nil
            }
        )
        return try repository.context.fetch(descriptor).map(TaskAppEntity.init(task:))
    }

    public func entities(matching query: String) throws -> [TaskAppEntity] {
        guard let repository else { throw TaskIntentRuntimeError.notConfigured }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var descriptor: FetchDescriptor<TaskItem>
        if trimmed.isEmpty {
            descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in task.deletedAt == nil && task.isTemplate == false }
            )
        } else {
            descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.deletedAt == nil
                        && task.title.localizedStandardContains(trimmed)
                        && task.isTemplate == false
                }
            )
        }
        descriptor.fetchLimit = 10
        return try repository.context.fetch(descriptor).map(TaskAppEntity.init(task:))
    }

    private func find(_ id: String, repository: TaskItemRepository) throws -> TaskItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == uuid && task.deletedAt == nil
            }
        )
        return try repository.context.fetch(descriptor).first
    }
}

public enum TaskIntentRuntimeError: Error, Equatable {
    case notConfigured
    case emptyInput
    case taskNotFound
}

extension TaskIntentRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Nexus is not fully loaded yet. Try again in a moment."
        case .emptyInput: return "Task description cannot be empty."
        case .taskNotFound: return "The task could not be found."
        }
    }
}
#endif
