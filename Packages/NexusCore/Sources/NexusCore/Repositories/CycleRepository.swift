import Foundation
import SwiftData

public enum CycleRepositoryError: Error, Equatable {
    case invalidInterval(startAt: Date, endAt: Date)
}

/// CRUD + soft-delete lifecycle for `Cycle` (Tranche 2, Plan A foundation +
/// Plan C selection/query surface; `ProjectRepository` shape). Bound to a
/// single `ModelContext`; never share across actors.
///
/// Soft-delete is PLAIN (no cascade): assigned tasks KEEP their `cycleID` — a
/// dangling id resolves to "no cycle" at read time, exactly the `projectID`
/// dangling semantics (invariant I-C1). The status machine is manual +
/// assisted only (`upcoming → active → completed`) — nothing here runs on a
/// schedule and nothing moves tasks automatically.
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
        guard endAt > startAt else {
            throw CycleRepositoryError.invalidInterval(startAt: startAt, endAt: endAt)
        }
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

    /// Combined editor write (Plan C): rewrites name + interval in one save,
    /// rejecting an end date not after the start date.
    public func update(_ cycle: Cycle, name: String, startAt: Date, endAt: Date) throws {
        guard endAt > startAt else {
            throw CycleRepositoryError.invalidInterval(startAt: startAt, endAt: endAt)
        }
        cycle.name = name
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

    /// The `.active` cycle whose `startAt...endAt` contains `now`; ties resolve
    /// to the earliest `startAt`, then UUID string, deterministically. An
    /// `upcoming` cycle containing now is NOT current — the machine is manual.
    public func current(now reference: Date) throws -> Cycle? {
        let activeRaw = CycleStatus.active.rawValue
        let descriptor = FetchDescriptor<Cycle>(
            predicate: #Predicate { cycle in
                cycle.deletedAt == nil && cycle.statusRaw == activeRaw
            }
        )
        return try context.fetch(descriptor)
            .filter { $0.startAt <= reference && reference <= $0.endAt }
            .min { lhs, rhs in
                if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// The earliest not-completed cycle starting strictly after `now` — the
    /// "next cycle" target of the end-of-cycle move prompt.
    public func next(now reference: Date) throws -> Cycle? {
        let completedRaw = CycleStatus.completed.rawValue
        let descriptor = FetchDescriptor<Cycle>(
            predicate: #Predicate { cycle in
                cycle.deletedAt == nil && cycle.statusRaw != completedRaw && cycle.startAt > reference
            }
        )
        return try context.fetch(descriptor)
            .min { lhs, rhs in
                if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Live, non-template tasks assigned to the cycle (spec §4.2 query:
    /// `cycleID == id && deletedAt == nil && isTemplate == false`), sorted by
    /// the shared manual-order comparator.
    public func tasks(in cycleID: UUID) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.cycleID == cycleID && task.deletedAt == nil && task.isTemplate == false
            }
        )
        return try context.fetch(descriptor).sorted(by: TaskItemRepository.assignmentOrder)
    }
}
