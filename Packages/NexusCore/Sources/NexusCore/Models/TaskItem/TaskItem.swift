import Foundation
import SwiftData

/// Production Linkable for the Tasks Module (Phase 1b+). `DebugItem` remains as a
/// test/preview fixture and vestigial schema entry.
@Model
public final class TaskItem: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.task
    public var title: String = ""
    public var body: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public var dueAt: Date?
    public var startAt: Date?
    public var endAt: Date?
    public var snoozedUntil: Date?
    public var statusRaw: String = TaskStatus.open.rawValue
    public var priorityRaw: Int = TaskPriority.none.rawValue
    public var tags: [String] = []
    public var recurrenceRule: String?
    public var recurrenceParentId: UUID?
    public var lastCompletedAt: Date?
    /// Hierarchy: pointer to the parent `TaskItem.id`. nil = root task.
    public var parentTaskID: UUID?

    /// Drop-dead deadline. Semantically distinct from `dueAt`: `dueAt` is when
    /// the task is supposed to start/be done by the user; `deadlineAt` is the
    /// hard external deadline. Either, both, or neither may be set.
    public var deadlineAt: Date?

    /// Project assignment (Phase 1i scaffold). nil = unassigned (Inbox).
    public var projectID: UUID?

    /// Section within a project. nil = project root or unassigned.
    public var sectionID: UUID?

    public var orderIndex: Double?
    public var pinnedAsFocus: Bool = false

    /// External system identifier for idempotent imports.
    /// Format convention: "<source>:<id>" e.g. "todoist:8237162", "linear:KP-100".
    public var externalSourceID: String?

    /// Raw original record from the source system, opaque blob.
    /// Used for conflict detection and re-migration.
    public var externalSourceMetadata: Data?

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        dueAt: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        deadlineAt: Date? = nil,
        priority: TaskPriority = .none,
        status: TaskStatus = .open,
        tags: [String] = [],
        recurrenceRule: String? = nil,
        recurrenceParentId: UUID? = nil,
        parentTaskID: UUID? = nil,
        projectID: UUID? = nil,
        sectionID: UUID? = nil,
        orderIndex: Double? = nil,
        pinnedAsFocus: Bool = false
    ) {
        self.id = id
        self.kind = .task
        self.title = title
        self.body = body
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.dueAt = dueAt
        self.startAt = startAt
        self.endAt = endAt
        self.snoozedUntil = nil
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.tags = tags
        self.recurrenceRule = recurrenceRule
        self.recurrenceParentId = recurrenceParentId
        self.lastCompletedAt = nil
        self.parentTaskID = parentTaskID
        self.deadlineAt = deadlineAt
        self.projectID = projectID
        self.sectionID = sectionID
        self.orderIndex = orderIndex
        self.pinnedAsFocus = pinnedAsFocus
    }

    public var status: TaskStatus {
        TaskStatus(rawValue: statusRaw) ?? .open
    }

    public var priority: TaskPriority {
        TaskPriority(rawValue: priorityRaw) ?? .none
    }

    /// Flattens title + body + tags into a single string for FTS tokenization.
    public var searchableText: String {
        var parts: [String] = [title]
        if !body.isEmpty {
            parts.append(body)
        }
        if !tags.isEmpty {
            parts.append(tags.joined(separator: " "))
        }
        return parts.joined(separator: "\n")
    }
}
