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

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
        self.links = LinkRepository(context: context)
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
        return label
    }

    public func rename(_ label: Label, to name: String) throws {
        label.name = name
        label.updatedAt = now()
        try context.save()
    }

    /// Soft-deletes a label (`deletedAt` stamped). Does NOT remove `.labeled`
    /// edges pointing at it — readers filter soft-deleted labels out via
    /// `labels(for:)`, which resolves edges to live `Label` rows.
    public func softDelete(_ label: Label) throws {
        label.deletedAt = now()
        label.updatedAt = now()
        try context.save()
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

    /// Idempotently seeds the system labels (spec §7). Each `SystemLabel` is created
    /// with its DETERMINISTIC stable `id` (`SystemLabel.id`) so the seed converges
    /// across devices — CloudKit forbids `@Attribute(.unique)`, so a fresh `UUID()`
    /// per launch would let two first-launching devices double-seed by name; a fixed
    /// id makes the two inserts merge into one record. A row is skipped if either its
    /// stable id OR (legacy) its case-insensitive name already exists. Missing ones
    /// are created with `isSystem = true`. Safe to run repeatedly (V11 migration step).
    public func seedSystemLabels() throws {
        let existing = try allActive()
        var byID: [UUID: Label] = [:]
        var byName: [String: Label] = [:]
        for label in existing {
            byID[label.id] = label
            byName[label.name.lowercased()] = label
        }
        let stamp = now()
        var didInsert = false
        for system in SystemLabel.allCases
        where byID[system.id] == nil && byName[system.name.lowercased()] == nil {
            let label = Label(
                id: system.id,
                name: system.name,
                glyphKey: system.glyphKey,
                group: system.group,
                isSystem: true
            )
            label.createdAt = stamp
            label.updatedAt = stamp
            context.insert(label)
            didInsert = true
        }
        if didInsert {
            try context.save()
        }
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
