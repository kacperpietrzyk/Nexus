import Foundation
import SwiftData

/// Production Linkable for the Tasks Module (Phase 1b+). `DebugItem` remains as a
/// test/preview fixture and vestigial schema entry.
@Model
public final class TaskItem: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.task
    public var title: String = ""
    /// LEGACY — superseded by `noteRef` → `Note` (Notes content layer, spec
    /// §4.2). The physical column is intentionally kept present (not deleted) so
    /// the V8→V9 `body`→`Note` conversion can read existing content out of it to
    /// create `Note`s; deleting the stored property would make the shared-model
    /// versioned schema unable to read it during that conversion, silently losing
    /// user content. (That conversion runs as post-open code, not a migration
    /// stage — see `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded`.) App
    /// logic no longer reads this — all readers repoint onto `noteRef`. The
    /// physical column is retired in a later schema once V9 migration is proven.
    public var body: String = ""
    /// Pointer to the `Note` holding this task's rich content (lazy — only set
    /// when content is non-empty; see spec §8 lifecycle). nil = no note.
    public var noteRef: UUID?
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

    /// JSON-encoded `[ReminderRule]`. `Data?`-backed (like
    /// `externalSourceMetadata`) to avoid SwiftData/CloudKit mirroring sharp
    /// edges with arrays of custom Codable structs. nil = no reminders.
    public var remindersData: Data?

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        noteRef: UUID? = nil,
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
        self.noteRef = noteRef
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

    /// Decoded view over `remindersData`. Setting to an empty array clears the
    /// stored blob. SwiftData persists only `remindersData`; this computed
    /// property is not part of the schema.
    public var reminders: [ReminderRule] {
        get {
            guard let remindersData else { return [] }
            return (try? JSONDecoder().decode([ReminderRule].self, from: remindersData)) ?? []
        }
        set {
            remindersData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// Flattens title + tags into a single string for FTS tokenization. Rich
    /// content is no longer carried on the task (spec §4.2): it lives in a `Note`
    /// referenced by `noteRef`, indexed independently as a `Note` that links back
    /// to this task — so a search hit on note content still leads to the task via
    /// the Link graph, without deserializing blocks per list row.
    public var searchableText: String {
        var parts: [String] = [title]
        if !tags.isEmpty {
            parts.append(tags.joined(separator: " "))
        }
        return parts.joined(separator: "\n")
    }
}
