import Foundation
import SwiftData

/// CRUD + soft-delete over `ScheduledBlock`, wiring the `LinkKind.scheduledAs`
/// edge (task → block) on create (spec §4.1 / §17). `@MainActor` to match the
/// SwiftData isolation used across the repositories. One `context.save()` per
/// op (the `CommentRepository` save boundary).
///
/// The `taskID` field is the fast-query path; the `scheduledAs` Link keeps the
/// relation visible in the graph (and lets backlink/outgoing queries find the
/// block from the task). EventKit and the mirror event live entirely in the
/// `CalendarSyncReconciler` (a later step) — this repo only persists Nexus-side
/// state and never touches `externalEventID` write-back logic.
@MainActor
public struct ScheduledBlockRepository {
    private let context: ModelContext
    private let links: LinkRepository
    private let now: () -> Date

    public init(
        context: ModelContext,
        links: LinkRepository? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.links = links ?? LinkRepository(context: context)
        self.now = now
    }

    // MARK: - Create

    /// Insert a block and wire the `scheduledAs` edge from its task. Idempotent
    /// on the edge (`findOrCreate`) so a re-run never duplicates the link.
    @discardableResult
    public func create(
        taskID: UUID,
        start: Date,
        end: Date,
        title: String = "",
        status: ScheduledBlockStatus = .proposed,
        origin: ScheduledBlockOrigin = .auto,
        externalEventID: String? = nil
    ) throws -> ScheduledBlock {
        let block = ScheduledBlock(
            taskID: taskID,
            start: start,
            end: end,
            title: title,
            status: status,
            origin: origin,
            externalEventID: externalEventID
        )
        context.insert(block)
        _ = try links.findOrCreate(
            from: (.task, taskID),
            to: (.scheduledBlock, block.id),
            linkKind: .scheduledAs
        )
        try context.save()
        return block
    }

    /// Persist a scheduler `BlockProposal` as a live `proposed` / `auto` block,
    /// wiring its edge. Proposals are detached value objects until persisted here.
    @discardableResult
    public func persistProposal(_ proposal: BlockProposal) throws -> ScheduledBlock {
        try create(
            taskID: proposal.taskID,
            start: proposal.start,
            end: proposal.end,
            title: proposal.title,
            status: .proposed,
            origin: .auto
        )
    }

    // MARK: - Read

    /// A single non-deleted block by id, or nil.
    public func find(_ id: UUID) throws -> ScheduledBlock? {
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        return try context.fetch(descriptor).first
    }

    /// Non-deleted blocks for a task, earliest start first.
    public func blocks(for taskID: UUID) throws -> [ScheduledBlock] {
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { $0.taskID == taskID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.start, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Non-deleted blocks overlapping `[start, end)`, earliest first. Used by the
    /// Today rail / grid to render blocks for a day.
    public func blocks(from start: Date, to end: Date) throws -> [ScheduledBlock] {
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { block in
                block.deletedAt == nil && block.start < end && block.end > start
            },
            sortBy: [SortDescriptor(\.start, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Update

    /// Move / resize a block. Callers that resize from a user drag also update
    /// the task estimate (spec §5) — that is the reconciler's job, not the
    /// repo's; this only persists the block.
    public func reschedule(_ block: ScheduledBlock, start: Date, end: Date) throws {
        block.start = start
        block.end = end
        block.updatedAt = now()
        try context.save()
    }

    /// Flip a block to `accepted` and record its mirror event id (invariant §14:
    /// `accepted ⇒ externalEventID != nil`). The actual EKEvent write happens in
    /// the reconciler; this persists the resulting state.
    public func markAccepted(_ block: ScheduledBlock, externalEventID: String) throws {
        block.statusRaw = ScheduledBlockStatus.accepted.rawValue
        block.externalEventID = externalEventID
        block.updatedAt = now()
        try context.save()
    }

    // MARK: - Delete

    /// Soft-delete a block (spec §14: `deletedAt`, CloudKit mirror). The
    /// `scheduledAs` edge is removed so the graph no longer points at a dead
    /// block.
    public func softDelete(_ block: ScheduledBlock) throws {
        block.deletedAt = now()
        block.updatedAt = now()
        let blockID = block.id
        let edges = try context.fetch(
            FetchDescriptor<Link>(predicate: #Predicate { $0.toID == blockID })
        )
        .filter { $0.toKind == .scheduledBlock && $0.linkKind == .scheduledAs }
        for edge in edges {
            context.delete(edge)
        }
        try context.save()
    }

    /// Cascade: soft-delete every live block for a task (task done/deleted path,
    /// spec §8). Returns the deleted blocks (so the reconciler can also remove
    /// any mirror events).
    @discardableResult
    public func softDeleteAll(for taskID: UUID) throws -> [ScheduledBlock] {
        let blocks = try blocks(for: taskID)
        for block in blocks {
            block.deletedAt = now()
            block.updatedAt = now()
            let blockID = block.id
            let edges = try context.fetch(
                FetchDescriptor<Link>(predicate: #Predicate { $0.toID == blockID })
            )
            .filter { $0.toKind == .scheduledBlock && $0.linkKind == .scheduledAs }
            for edge in edges {
                context.delete(edge)
            }
        }
        try context.save()
        return blocks
    }
}
