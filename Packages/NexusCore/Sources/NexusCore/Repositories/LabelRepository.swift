import Foundation
import SwiftData

/// An endpoint a `Label` can hang off (Projects tier, spec §4.4). Labels attach to
/// tasks and projects only.
public enum LabelEndpointKind: Sendable {
    case task
    case project

    var itemKind: ItemKind {
        switch self {
        case .task: return .task
        case .project: return .project
        }
    }
}

/// CRUD for `Label` plus the many-to-many label graph (`LinkKind.labeled`) on task
/// and project endpoints, the single-select policy (invariant I5, spec §7), the
/// idempotent system-label seed, and the agent-queue query (spec §8 / §10).
///
/// The edge carries no group, so single-select resolves each existing labeled edge
/// back to its `Label` to compare groups (advisor note): assigning a `domain` (or
/// `gate`) label deletes the **edge** — never the `Label` row — to any prior label
/// of the same group on that endpoint. `free` accumulates. Bound to a single
/// `ModelContext`; never share across actors.
@MainActor
public final class LabelRepository {
    public let context: ModelContext
    public let now: () -> Date
    private let links: LinkRepository
    /// Search/Spotlight observers (mirrors `LinkableRepository`). When non-empty, the
    /// repo fires `didUpsert` after create/rename (the indexed `name` changes) and
    /// `didSoftDelete` after `softDelete`. Default empty so existing callers and tests
    /// are unaffected. Assign/remove edge ops don't touch `name`, so they don't fan out.
    private let observers: [any LinkableObserver]

    public init(
        context: ModelContext,
        now: @escaping () -> Date = { .now },
        observers: [any LinkableObserver] = []
    ) {
        self.context = context
        self.now = now
        self.links = LinkRepository(context: context)
        self.observers = observers
    }

    /// Fans out an upsert for `label` (snapshot built on `@MainActor`, awaited into
    /// each observer's actor via detached `Task`). Mirrors `LinkableRepository`.
    private func broadcastUpsert(for label: Label) {
        guard !observers.isEmpty else { return }
        let document = IndexedDocument(label)
        for observer in observers {
            _Concurrency.Task { await observer.didUpsert(document) }
        }
    }

    // MARK: - CRUD

    @discardableResult
    public func create(
        name: String,
        glyphKey: String = "",
        group: LabelGroup = .free,
        isSystem: Bool = false
    ) throws -> Label {
        let stamp = now()
        let label = Label(name: name, glyphKey: glyphKey, group: group, isSystem: isSystem)
        label.createdAt = stamp
        label.updatedAt = stamp
        context.insert(label)
        try context.save()
        broadcastUpsert(for: label)
        return label
    }

    public func rename(_ label: Label, to name: String) throws {
        label.name = name
        label.updatedAt = now()
        try context.save()
        broadcastUpsert(for: label)
    }

    /// Soft-deletes a label (`deletedAt` stamped). Does NOT remove `.labeled`
    /// edges pointing at it — readers filter soft-deleted labels out via
    /// `labels(for:)`, which resolves edges to live `Label` rows.
    public func softDelete(_ label: Label) throws {
        label.deletedAt = now()
        label.updatedAt = now()
        try context.save()
        let id = label.id
        for observer in observers {
            _Concurrency.Task { await observer.didSoftDelete(kind: .label, id: id) }
        }
    }

    public func find(id: UUID) throws -> Label? {
        let descriptor = FetchDescriptor<Label>(
            predicate: #Predicate { label in label.id == id }
        )
        return try context.fetch(descriptor).first
    }

    public func allActive() throws -> [Label] {
        let descriptor = FetchDescriptor<Label>(
            predicate: #Predicate { label in label.deletedAt == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Graph (LinkKind.labeled)

    /// The live (non-soft-deleted) labels attached to an endpoint, resolved from
    /// the `.labeled` edges. Edges pointing at a soft-deleted label are skipped.
    public func labels(for endpoint: (LabelEndpointKind, UUID)) throws -> [Label] {
        try labeledEdges(from: endpoint).compactMap { edge in
            guard let label = try find(id: edge.toID), label.deletedAt == nil else { return nil }
            return label
        }
    }

    /// Assigns a label to an endpoint, enforcing single-select for `domain`/`gate`
    /// (invariant I5): for a single-select group, any prior `.labeled` **edge** to
    /// a label of the same group on this endpoint is deleted first (the label rows
    /// are untouched). `free` accumulates. Idempotent on the edge itself.
    @discardableResult
    public func assign(_ label: Label, to endpoint: (LabelEndpointKind, UUID)) throws -> Link {
        if label.group.isSingleSelect {
            let group = label.group
            for existing in try labels(for: endpoint) where existing.group == group && existing.id != label.id {
                try removeEdges(from: endpoint, toLabelID: existing.id)
            }
        }
        return try links.findOrCreate(
            from: (endpoint.0.itemKind, endpoint.1),
            to: (.label, label.id),
            linkKind: .labeled
        )
    }

    /// Removes a label from an endpoint by deleting the `.labeled` edge(s). The
    /// `Label` row is untouched (labels are shared/reusable).
    public func remove(_ label: Label, from endpoint: (LabelEndpointKind, UUID)) throws {
        try removeEdges(from: endpoint, toLabelID: label.id)
    }

    private func labeledEdges(from endpoint: (LabelEndpointKind, UUID)) throws -> [Link] {
        try links.outgoing(from: (endpoint.0.itemKind, endpoint.1)).filter { $0.linkKind == .labeled }
    }

    private func removeEdges(from endpoint: (LabelEndpointKind, UUID), toLabelID labelID: UUID) throws {
        for edge in try labeledEdges(from: endpoint) where edge.toID == labelID {
            try links.delete(edge)
        }
    }

    // MARK: - Seed

    /// Idempotently seeds the system labels (spec §7) via the shared
    /// `SystemLabelSeeder`, which both this @MainActor path and the non-isolated
    /// V11 migration delegate to so they can't drift (P4). A `SystemLabel` is
    /// skipped only when its stable id already exists (live or tombstoned) or a
    /// live *system* label shares its `(group, name)` — a user's same-named free
    /// label no longer blocks it. Safe to run repeatedly.
    public func seedSystemLabels() throws {
        try SystemLabelSeeder.seed(in: context, now: now)
    }

    // MARK: - Agent queue (spec §8 / §10)

    /// The MCP-exposed work queue for an agent: tasks with `assignedAgent == agent`,
    /// `workflowState ∈ {todo, inProgress}`, and not soft-deleted (spec §8). The
    /// `{todo,inProgress}` filter already implies an open task via `forcedStatus`,
    /// so "not closed" reduces to the `deletedAt` filter. `#Predicate` cannot
    /// capture enums, so raw values are pre-bound and matched as strings.
    public func agentQueue(for agent: AgentAssignee) throws -> [TaskItem] {
        let agentRaw = agent.rawValue
        let todoRaw = WorkflowState.todo.rawValue
        let inProgressRaw = WorkflowState.inProgress.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil
                    && task.assignedAgent == agentRaw
                    && (task.workflowStateRaw == todoRaw || task.workflowStateRaw == inProgressRaw)
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }
}
