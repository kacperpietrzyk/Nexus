import Foundation
import SwiftData

public enum AgentMemoryScopeFilter: Equatable, Sendable {
    case global
    case project
    case tag
    case exact(String)
    case prefix(String)

    fileprivate func matches(_ scope: String) -> Bool {
        switch self {
        case .global:
            return scope == "global"
        case .project:
            return scope.hasPrefix("project:")
        case .tag:
            return scope.hasPrefix("tag:")
        case .exact(let value):
            return scope == value
        case .prefix(let value):
            return scope.hasPrefix(value)
        }
    }
}

public final class AgentMemoryStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func upsert(
        scope: String,
        key: String,
        content: String,
        source: AgentMemorySource = .agent,
        confidence: Double = 1.0,
        linkedItemIDs: [UUID] = [],
        now: Date = .now
    ) throws -> UUID {
        if let existing = try find(scope: scope, key: key) {
            existing.content = content
            existing.source = source
            existing.confidence = confidence
            existing.linkedItemIDs = linkedItemIDs
            existing.updatedAt = now
            try context.save()
            return existing.id
        }

        let entry = AgentMemoryEntry(
            scope: scope,
            key: key,
            content: content,
            source: source,
            createdAt: now,
            updatedAt: now,
            confidence: confidence,
            linkedItemIDs: linkedItemIDs
        )
        context.insert(entry)
        try context.save()
        return entry.id
    }

    public func find(scope: String, key: String) throws -> AgentMemoryEntry? {
        try context.fetch(
            FetchDescriptor<AgentMemoryEntry>(
                predicate: #Predicate { $0.scope == scope && $0.key == key }
            )
        ).first { $0.deletedAt == nil }
    }

    public func find(id: UUID, includeDeleted: Bool = false) throws -> AgentMemoryEntry? {
        let entry = try context.fetch(
            FetchDescriptor<AgentMemoryEntry>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
        guard includeDeleted || entry?.deletedAt == nil else {
            return nil
        }
        return entry
    }

    public func list(scope: String) throws -> [AgentMemoryEntry] {
        try list(matching: .exact(scope))
    }

    public func list(matching scopeFilter: AgentMemoryScopeFilter) throws -> [AgentMemoryEntry] {
        try sortedEntries()
            .filter { $0.deletedAt == nil }
            .filter { scopeFilter.matches($0.scope) }
    }

    public func recent(scope: String, limit: Int = 5) throws -> [AgentMemoryEntry] {
        guard limit > 0 else { return [] }

        return Array(try list(scope: scope).prefix(limit))
    }

    public func softDelete(id: UUID, now: Date = .now) throws {
        guard let entry = try find(id: id, includeDeleted: true) else {
            return
        }

        entry.deletedAt = now
        entry.updatedAt = now
        try context.save()
    }

    public func delete(id: UUID) throws {
        guard let entry = try find(id: id, includeDeleted: true) else {
            return
        }

        context.delete(entry)
        try context.save()
    }

    private func sortedEntries() throws -> [AgentMemoryEntry] {
        try context.fetch(
            FetchDescriptor<AgentMemoryEntry>(
                sortBy: [
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse),
                ]
            )
        )
    }
}
