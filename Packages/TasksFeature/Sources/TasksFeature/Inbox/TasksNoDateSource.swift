import Foundation
import InboxShell
import NexusCore
import SwiftData

public actor TasksNoDateSource: InboxSource {
    public let id = "tasks.no-date"
    public let displayName = "Tasks without dates"
    public let iconName = "tray"

    private let repository: TaskItemRepository

    public init(repository: TaskItemRepository) {
        self.repository = repository
    }

    public func items() async throws -> [InboxItem] {
        let sourceID = id
        return try await MainActor.run {
            let archivedProjectIDs =
                (try? ProjectRepository(context: repository.context).archivedProjectIDs()) ?? []
            return try TodayQuery()
                .noDate(excludingProjectIDs: archivedProjectIDs)
                .apply(in: repository.context)
                .map { task in
                    InboxItem(
                        id: task.id,
                        sourceID: sourceID,
                        title: task.title,
                        body: task.body.isEmpty ? nil : task.body,
                        due: task.dueAt,
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
            try repository.softDelete(task)
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
