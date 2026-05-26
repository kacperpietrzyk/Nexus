import Foundation
import SwiftData

public final class AgentThreadStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func create(
        title: String,
        projectID: UUID? = nil,
        modelHint: String? = nil
    ) throws -> UUID {
        let thread = AgentThread(title: title, projectID: projectID, modelHint: modelHint)
        context.insert(thread)
        try context.save()
        return thread.id
    }

    public func get(id: UUID) throws -> AgentThread? {
        try context.fetch(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }

    public func allActive() throws -> [AgentThread] {
        try context.fetch(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { $0.archivedAt == nil },
                sortBy: [
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse),
                ]
            )
        )
    }

    public func allArchived() throws -> [AgentThread] {
        try context.fetch(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { $0.archivedAt != nil },
                sortBy: [
                    SortDescriptor(\.archivedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse),
                ]
            )
        )
    }

    public func archive(id: UUID, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.archivedAt = now
        thread.updatedAt = now
        try context.save()
    }

    public func touch(id: UUID, now: Date = .now) throws {
        guard let thread = try get(id: id) else { return }
        thread.updatedAt = now
        try context.save()
    }
}
