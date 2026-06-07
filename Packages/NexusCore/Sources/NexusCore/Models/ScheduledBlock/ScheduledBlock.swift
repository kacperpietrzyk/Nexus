import Foundation
import SwiftData

/// A proposed or accepted time block for a `TaskItem` (Calendar / Motion-AI
/// module, spec §4.1). A block is a first-class graph entity
/// (`ItemKind.scheduledBlock`), linked back to its task by `taskID` (fast query,
/// mirroring `parentTaskID`) and by a `LinkKind.scheduledAs` edge (graph
/// uniformity).
///
/// Lifecycle (spec §8 / §14): a `proposed` block lives only inside Nexus
/// (`externalEventID == nil`). On accept the `CalendarSyncReconciler` writes a
/// mirror `EKEvent` into the dedicated "Nexus" calendar and stores its
/// identifier on `externalEventID`, flipping `status` to `accepted`. The
/// scheduler never moves an accepted block (anti-thrash).
///
/// Every stored property is defaulted/optional so the model is CloudKit-mirror
/// safe (private DB), mirroring `TaskItem` / `Note`. `kind` is stored (not
/// computed) so it can be queried by predicate without fetching the concrete
/// subtype, per `Linkable`.
@Model
public final class ScheduledBlock: Linkable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.scheduledBlock

    /// `Linkable` requires a settable `title`. A block's title is derived from
    /// its task (the mirror event's title is the task title); it is stored so
    /// the block can stand alone in the graph and so list/diagnostic surfaces
    /// have a label without a task fetch. Not search-indexed (blocks are not
    /// `Searchable`).
    public var title: String = ""

    /// The `TaskItem.id` this block schedules. Direct field for fast queries
    /// (pattern mirrors `parentTaskID`); the `LinkKind.scheduledAs` edge carries
    /// the same relation in the graph.
    public var taskID: UUID = UUID()

    public var start: Date = Date.now
    /// `end - start` is the block's duration.
    public var end: Date = Date.now

    public var statusRaw: String = ScheduledBlockStatus.proposed.rawValue
    public var originRaw: String = ScheduledBlockOrigin.auto.rawValue

    /// `EKEvent.eventIdentifier` of the mirror event in the "Nexus" calendar.
    /// nil while `proposed`; set on accept (invariant §14).
    public var externalEventID: String?

    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    /// Soft-delete (consistent with the other models; CloudKit mirror).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        start: Date,
        end: Date,
        title: String = "",
        status: ScheduledBlockStatus = .proposed,
        origin: ScheduledBlockOrigin = .auto,
        externalEventID: String? = nil
    ) {
        self.id = id
        self.kind = .scheduledBlock
        self.title = title
        self.taskID = taskID
        self.start = start
        self.end = end
        self.statusRaw = status.rawValue
        self.originRaw = origin.rawValue
        self.externalEventID = externalEventID
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    /// Get-only view over `statusRaw` (mirrors `TaskItem.status`). Unknown raw
    /// values fall back to `.proposed`.
    public var status: ScheduledBlockStatus {
        ScheduledBlockStatus(rawValue: statusRaw) ?? .proposed
    }

    /// Get-only view over `originRaw` (mirrors `TaskItem.priority`). Unknown raw
    /// values fall back to `.auto`.
    public var origin: ScheduledBlockOrigin {
        ScheduledBlockOrigin(rawValue: originRaw) ?? .auto
    }
}
