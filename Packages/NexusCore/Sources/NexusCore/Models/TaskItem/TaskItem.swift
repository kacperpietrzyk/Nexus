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

    /// Optional tracker state machine (Projects tier, spec §4.2). `nil` = a plain
    /// GTD task that runs purely on `status` (invariant I7). When non-nil it
    /// deterministically drives `status` via `TaskItemRepository` reconciliation
    /// (spec §5). Read through the `workflowState` accessor. Stored as `String?`
    /// because SwiftData + CloudKit reject enum-typed properties. Additive/optional.
    public var workflowStateRaw: String?

    /// Agent this task is assigned to (Projects tier, spec §4.5 / §8;
    /// `AgentAssignee` raw). `nil` = self. Pure metadata — never affects
    /// scheduling/visibility (invariant I8). Read through the `agent` accessor.
    public var assignedAgent: String?

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

    /// Estimated duration in seconds (Calendar / Motion-AI module, spec §4.2).
    /// nil = no estimate. The scheduler uses this to size a `ScheduledBlock`;
    /// `startAt`/`endAt` stay generic (recurrence/deadline) and are NOT
    /// repurposed for scheduling.
    public var estimatedDurationSeconds: Int?

    /// Provenance of `estimatedDurationSeconds` (`DurationSource` raw). nil = no
    /// estimate yet. Read via the `durationSource` accessor. Governs the
    /// override cascade: `.explicit` always wins and feeds the history corpus.
    public var durationSourceRaw: String?

    /// Cycle assignment (Tranche 2, Linear L1). nil = no cycle. Raw pointer to
    /// `Cycle.id`, follows the `projectID` precedent — no @Relationship. A
    /// dangling id (cycle soft-deleted) resolves to "no cycle" at read time.
    public var cycleID: UUID?

    /// Template flag (Tranche 2, Todoist T2). A template is inert: excluded
    /// from every operational query/notification/snapshot surface (invariant
    /// I-D1 — the exclusion sweep itself ships in Plan D). Defaulted
    /// non-optional Bool — the `pinnedAsFocus` precedent.
    public var isTemplate: Bool = false

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
        pinnedAsFocus: Bool = false,
        workflowState: WorkflowState? = nil,
        assignedAgent: AgentAssignee? = nil,
        estimatedDurationSeconds: Int? = nil,
        durationSource: DurationSource? = nil,
        cycleID: UUID? = nil,
        isTemplate: Bool = false
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
        self.workflowStateRaw = workflowState?.rawValue
        self.assignedAgent = assignedAgent?.rawValue
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.durationSourceRaw = durationSource?.rawValue
        self.cycleID = cycleID
        self.isTemplate = isTemplate
    }

    public var status: TaskStatus {
        TaskStatus(rawValue: statusRaw) ?? .open
    }

    public var priority: TaskPriority {
        TaskPriority(rawValue: priorityRaw) ?? .none
    }

    /// Get-only view over `workflowStateRaw` (Projects tier, spec §4.2). `nil` =
    /// GTD task (machine inactive) OR an unknown stored raw. Mutating the machine
    /// goes through `TaskItemRepository` reconciliation, never a raw setter.
    public var workflowState: WorkflowState? {
        workflowStateRaw.flatMap(WorkflowState.init(rawValue:))
    }

    /// Get-only view over `assignedAgent` (Projects tier, spec §4.5). `nil` =
    /// self, or an unknown stored raw.
    public var agent: AgentAssignee? {
        assignedAgent.flatMap(AgentAssignee.init(rawValue:))
    }

    /// Get-only view over `durationSourceRaw` (mirrors `status`/`priority`).
    /// nil when no estimate has been recorded or the raw value is unknown.
    public var durationSource: DurationSource? {
        durationSourceRaw.flatMap(DurationSource.init(rawValue:))
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
