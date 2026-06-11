import Foundation
import SwiftData

/// CRUD + soft-delete lifecycle for `Cycle` (Tranche 2, Plan A foundation;
/// `ProjectRepository` shape). Bound to a single `ModelContext`; never share
/// across actors.
///
/// Soft-delete is PLAIN (no cascade): assigned tasks KEEP their `cycleID` — a
/// dangling id resolves to "no cycle" at read time, exactly the `projectID`
/// dangling semantics (invariant I-C1). `current(now:)`/`next(now:)` and
/// `TaskItemRepository.assignCycle` are Plan C.
@MainActor
public final class CycleRepository {
    public let context: ModelContext
    public let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    @discardableResult
    public func create(name: String, startAt: Date, endAt: Date) throws -> Cycle {
        let stamp = now()
        let cycle = Cycle(name: name, startAt: startAt, endAt: endAt)
        cycle.createdAt = stamp
        cycle.updatedAt = stamp
        context.insert(cycle)
        try context.save()
        return cycle
    }

    public func rename(_ cycle: Cycle, to name: String) throws {
        cycle.name = name
        cycle.updatedAt = now()
        try context.save()
    }

    public func setDates(_ cycle: Cycle, startAt: Date, endAt: Date) throws {
        cycle.startAt = startAt
        cycle.endAt = endAt
        cycle.updatedAt = now()
        try context.save()
    }

    /// Manual status machine (`upcoming → active → completed`). No
    /// auto-rollover and no transition validation here — the planning surface
    /// drives explicit user actions (Plan C, invariant I-C1).
    public func setStatus(_ status: CycleStatus, on cycle: Cycle) throws {
        cycle.statusRaw = status.rawValue
        cycle.updatedAt = now()
        try context.save()
    }

    /// Plain soft-delete; assigned tasks keep their `cycleID` (see type doc).
    public func softDelete(_ cycle: Cycle) throws {
        let stamp = now()
        cycle.deletedAt = stamp
        cycle.updatedAt = stamp
        try context.save()
    }

    /// Non-deleted cycles, earliest `startAt` first.
    public func allActive() throws -> [Cycle] {
        let descriptor = FetchDescriptor<Cycle>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// A cycle by id, or nil. Does not filter soft-deleted (the
    /// `ProjectRepository.find` contract — callers resolve dangling ids).
    public func find(id: UUID) throws -> Cycle? {
        let descriptor = FetchDescriptor<Cycle>(
            predicate: #Predicate { cycle in cycle.id == id }
        )
        return try context.fetch(descriptor).first
    }
}
