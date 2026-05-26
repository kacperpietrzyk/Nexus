import Foundation
import InboxShell
import NexusCore
import SwiftData

public actor TasksSnoozedSource: InboxSource {
    public let id = "tasks.snoozed"
    public let displayName = "Snoozed tasks"
    public let iconName = "clock"

    private let repository: TaskItemRepository
    private let now: @Sendable () -> Date

    public init(repository: TaskItemRepository, now: @escaping @Sendable () -> Date = { .now }) {
        self.repository = repository
        self.now = now
    }

    public func items() async throws -> [InboxItem] {
        let sourceID = id
        let nowValue = now()
        return try await MainActor.run {
            let status = TaskStatus.snoozed.rawValue
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.deletedAt == nil && task.statusRaw == status
                },
                sortBy: [SortDescriptor(\.snoozedUntil, order: .forward)]
            )
            return try repository.context.fetch(descriptor)
                .filter { ($0.snoozedUntil ?? .distantPast) > nowValue }
                .map { task in
                    InboxItem(
                        id: task.id,
                        sourceID: sourceID,
                        title: task.title,
                        body: task.body.isEmpty ? nil : task.body,
                        due: task.snoozedUntil,
                        tags: task.tags,
                        createdAt: task.createdAt
                    )
                }
        }
    }

    public func archive(_ item: InboxItem) async throws {
        let id = item.id
        try await MainActor.run {
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.id == id && task.deletedAt == nil
                }
            )
            guard let task = try repository.context.fetch(descriptor).first else { return }
            // `repository.unsnooze` guards on `snoozedUntil <= now` to avoid waking
            // sleeping tasks early; the snoozed inbox only surfaces future-snoozed
            // tasks, so calling it here is a silent no-op. Use `update` instead so
            // we still get the `updatedAt` bump and notification reschedule hook.
            try repository.update(task) { task in
                task.snoozedUntil = nil
                task.statusRaw = TaskStatus.open.rawValue
            }
        }
    }

    public func snooze(_ item: InboxItem, until date: Date) async throws {
        let id = item.id
        try await MainActor.run {
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.id == id && task.deletedAt == nil
                }
            )
            guard let task = try repository.context.fetch(descriptor).first else { return }
            try repository.snooze(task, until: date)
        }
    }
}
