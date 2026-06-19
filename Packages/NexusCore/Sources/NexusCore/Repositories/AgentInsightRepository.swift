import Foundation
import SwiftData

@MainActor
public struct AgentInsightRepository {
    private let context: ModelContext
    private let now: () -> Date

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    /// Open (unresolved) records, newest first.
    public func open() throws -> [AgentInsightRecord] {
        try context.fetch(FetchDescriptor<AgentInsightRecord>(
            predicate: #Predicate { $0.resolvedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    /// Insert unless an open record with the same `dedupeKey` already exists.
    @discardableResult
    public func add(kind: String, dedupeKey: String, title: String, proposalJSON: String) throws -> AgentInsightRecord {
        if let existing = try open().first(where: { $0.dedupeKey == dedupeKey }) { return existing }
        let record = AgentInsightRecord(
            kind: kind, dedupeKey: dedupeKey, title: title,
            proposalJSON: proposalJSON, createdAt: now()
        )
        context.insert(record)
        try context.save()
        return record
    }

    public func resolve(id: UUID) throws {
        let target = id
        guard let record = try context.fetch(FetchDescriptor<AgentInsightRecord>(
            predicate: #Predicate { $0.id == target }
        )).first else { return }
        record.resolvedAt = now()
        try context.save()
    }
}
