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
            let tasks = try TodayQuery()
                .noDate(excludingProjectIDs: archivedProjectIDs)
                .apply(in: repository.context)
            return Self.makeItems(from: tasks, sourceID: sourceID, context: repository.context)
        }
    }

    /// Cheap COUNT path (no materialization) for the unread/tab badges, so the
    /// Inbox can window the item list while the counts stay true. NOTE: this
    /// counts via `fetchCount` on the storage predicate, so it includes the few
    /// archived-project no-date tasks the post-filter would drop — a documented,
    /// negligible over-count vs the windowed list.
    public func count() async throws -> Int {
        try await MainActor.run {
            try TodayQuery().noDateInboxWindow().count(in: repository.context)
        }
    }

    /// Windowed fetch: the first `limit` no-date tasks in `createdAt`-desc order
    /// (the Inbox's global comparator), so a cold entry materializes a page, not
    /// ~1383 rows. Uses the raw-cursor page so the archived-project post-filter
    /// stays gap-free.
    public func items(limit: Int) async throws -> [InboxItem] {
        let sourceID = id
        return try await MainActor.run {
            let archivedProjectIDs =
                (try? ProjectRepository(context: repository.context).archivedProjectIDs()) ?? []
            let page = try TodayQuery()
                .noDateInboxWindow(excludingProjectIDs: archivedProjectIDs)
                .page(in: repository.context, rawOffset: 0, rawLimit: limit)
            return Self.makeItems(from: page.items, sourceID: sourceID, context: repository.context)
        }
    }

    @MainActor
    private static func makeItems(
        from tasks: [TaskItem],
        sourceID: String,
        context: ModelContext
    ) -> [InboxItem] {
        let noteTextByID = taskInboxNoteTextByID(for: tasks, in: context)
        return tasks.map { task in
            InboxItem(
                id: task.id,
                sourceID: sourceID,
                title: task.title,
                body: taskInboxBody(for: task, noteTextByID: noteTextByID),
                due: task.dueAt,
                tags: task.tags,
                createdAt: task.createdAt
            )
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

    public func delete(_ item: InboxItem) async throws {
        try await archive(item)
    }

    public func restore(_ item: InboxItem) async throws {
        let id = item.id
        try await MainActor.run {
            // Fetch including soft-deleted (no `deletedAt == nil` predicate).
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in task.id == id }
            )
            guard let task = try repository.context.fetch(descriptor).first else { return }
            task.deletedAt = nil
            task.updatedAt = .now
            try repository.context.save()
        }
    }
}

@MainActor
func taskInboxNoteTextByID(for tasks: [TaskItem], in context: ModelContext) -> [UUID: String] {
    let noteIDs = Set(tasks.compactMap(\.noteRef))
    guard !noteIDs.isEmpty else { return [:] }
    // Predicated fetch: only the referenced live notes, instead of scanning the
    // whole Note table and filtering in memory. UUID `contains` over an array is
    // translatable by SwiftData. Output is identical to the old all-fetch path.
    let ids = Array(noteIDs)
    let descriptor = FetchDescriptor<Note>(
        predicate: #Predicate { $0.deletedAt == nil && ids.contains($0.id) }
    )
    guard let notes = try? context.fetch(descriptor) else { return [:] }
    return Dictionary(
        uniqueKeysWithValues: notes.map { note in
            if !note.plainText.isEmpty {
                return (note.id, note.plainText)
            }
            let text = (try? NotePlainTextFlattener.plainText(for: NoteContentCoder.decode(note.contentData))) ?? ""
            return (note.id, text)
        }
    )
}

@MainActor
func taskInboxBody(for task: TaskItem, noteTextByID: [UUID: String]) -> String? {
    let body = (task.noteRef.flatMap { noteTextByID[$0] } ?? task.body)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}
