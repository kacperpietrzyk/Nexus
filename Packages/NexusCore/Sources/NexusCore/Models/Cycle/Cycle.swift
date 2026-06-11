import Foundation
import SwiftData

/// A time-boxed sprint, Linear-style (Tranche 2, Linear L1). A `Cycle` is a
/// first-class graph entity (`ItemKind.cycle`); tasks point at it via the raw
/// `TaskItem.cycleID` pointer (the `projectID` precedent — no SwiftData
/// `@Relationship`). A dangling `cycleID` after a cycle soft-delete reads as
/// "no cycle" at read time (invariant I-C1).
///
/// Modeled on `Project` (Linkable + String-raw status machine + computed
/// `title` over `name`) and `ScheduledBlock` (defaulted `Date` fields). Every
/// stored property is defaulted/optional so the model is CloudKit-mirror safe
/// (private DB). `Linkable` for graph uniformity but NOT `Searchable` in v1
/// (mirrors `ScheduledBlock`).
@Model
public final class Cycle: Linkable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.cycle
    public var name: String = ""
    public var startAt: Date = Date.now
    public var endAt: Date = Date.now
    /// `CycleStatus` raw. Stored as `String` because SwiftData + CloudKit
    /// reject enum-typed properties (same comment as `Project.statusRaw`).
    public var statusRaw: String = CycleStatus.upcoming.rawValue
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        startAt: Date,
        endAt: Date,
        status: CycleStatus = .upcoming
    ) {
        self.id = id
        self.kind = .cycle
        self.name = name
        self.startAt = startAt
        self.endAt = endAt
        self.statusRaw = status.rawValue
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    /// `Linkable` requires a settable `title` (Project precedent).
    public var title: String {
        get { name }
        set { name = newValue }
    }

    /// Get-only view over `statusRaw` (mirrors `Project.status`). Falls back
    /// to `.upcoming` for an unknown stored raw.
    public var status: CycleStatus {
        CycleStatus(rawValue: statusRaw) ?? .upcoming
    }
}
