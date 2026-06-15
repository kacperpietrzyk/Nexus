import Foundation
import SwiftData

/// CRUD + in-memory application for `SavedFilter`. Bound to a single
/// `ModelContext`; never share across actors.
@MainActor
public final class SavedFilterRepository {
    public let context: ModelContext
    public let now: () -> Date
    public let calendar: Calendar

    public init(
        context: ModelContext,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.context = context
        self.now = now
        self.calendar = calendar
    }

    @discardableResult
    public func create(
        name: String,
        definition: FilterDefinition,
        icon: String = "line.3.horizontal.decrease.circle"
    ) throws -> SavedFilter {
        let filters = try all()
        let orderIndex = OrderIndex.midpoint(prev: filters.last?.orderIndex, next: nil)
        let stamp = now()
        let filter = try SavedFilter(name: name, icon: icon, definition: definition, orderIndex: orderIndex)
        filter.createdAt = stamp
        filter.updatedAt = stamp
        context.insert(filter)
        try context.save()
        return filter
    }

    public func update(
        _ filter: SavedFilter,
        name: String? = nil,
        definition: FilterDefinition? = nil
    ) throws {
        if let name {
            filter.name = name
        }
        if let definition {
            try filter.setDefinition(definition)
        }
        filter.updatedAt = now()
        try context.save()
    }

    public func reorder(_ filter: SavedFilter, between previous: SavedFilter?, and next: SavedFilter?) throws {
        filter.orderIndex = OrderIndex.midpoint(prev: previous?.orderIndex, next: next?.orderIndex)
        filter.updatedAt = now()
        try context.save()
    }

    public func delete(_ filter: SavedFilter) throws {
        let stamp = now()
        filter.deletedAt = stamp
        filter.updatedAt = stamp
        try context.save()
    }

    public func all() throws -> [SavedFilter] {
        let descriptor = FetchDescriptor<SavedFilter>(
            predicate: #Predicate { filter in filter.deletedAt == nil },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        return try context.fetch(descriptor)
    }

    public func find(_ id: UUID) throws -> SavedFilter? {
        let descriptor = FetchDescriptor<SavedFilter>(
            predicate: #Predicate { filter in
                filter.id == id && filter.deletedAt == nil
            }
        )
        return try context.fetch(descriptor).first
    }

    public func apply(_ filter: SavedFilter, now: Date? = nil) throws -> [TaskItem] {
        let definition = try filter.decodedDefinition()
        let stamp = now ?? self.now()
        let openStatus = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil && task.statusRaw == openStatus && task.isTemplate == false
            }
        )
        return try context.fetch(descriptor)
            .filter { definition.matches($0, now: stamp, calendar: calendar) }
            .sorted(by: TaskItemRepository.assignmentOrder)
    }
}
