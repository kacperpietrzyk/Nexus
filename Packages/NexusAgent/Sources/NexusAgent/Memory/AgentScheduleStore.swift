import Foundation
import SwiftData

public enum AgentScheduleOptionalFieldMutation<Value: Sendable>: Sendable {
    case unchanged
    case set(Value?)
}

public struct AgentScheduleStoreMutation: Sendable {
    public let name: String
    public let kind: AgentScheduleKind?
    public let cronExpression: String
    public let prompt: String
    public let threadID: UUID?
    public let projectID: AgentScheduleOptionalFieldMutation<UUID>
    public let modelHint: String?
    public let enabled: Bool

    public init(
        name: String,
        kind: AgentScheduleKind? = nil,
        cronExpression: String,
        prompt: String,
        threadID: UUID? = nil,
        projectID: AgentScheduleOptionalFieldMutation<UUID> = .unchanged,
        modelHint: String? = nil,
        enabled: Bool = true
    ) {
        self.name = name
        self.kind = kind
        self.cronExpression = cronExpression
        self.prompt = prompt
        self.threadID = threadID
        self.projectID = projectID
        self.modelHint = modelHint
        self.enabled = enabled
    }
}

public final class AgentScheduleStore: AgentScheduleStoreProviding {
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func create(
        name: String,
        kind: AgentScheduleKind = .builtIn,
        cronExpression: String,
        prompt: String,
        threadID: UUID? = nil,
        projectID: UUID? = nil,
        modelHint: String? = nil,
        enabled: Bool = true
    ) throws -> UUID {
        let schedule = AgentSchedule(
            name: name,
            kind: kind,
            cronExpression: cronExpression,
            prompt: prompt,
            threadID: threadID,
            projectID: projectID,
            modelHint: modelHint,
            enabled: enabled
        )
        context.insert(schedule)
        try context.save()
        return schedule.id
    }

    @discardableResult
    public func save(_ mutation: AgentScheduleStoreMutation, id: UUID? = nil) throws -> UUID {
        if let id, let schedule = try get(id: id) {
            schedule.name = mutation.name
            if let kind = mutation.kind {
                schedule.kind = kind
            }
            schedule.cronExpression = mutation.cronExpression
            schedule.prompt = mutation.prompt
            schedule.threadID = mutation.threadID
            switch mutation.projectID {
            case .unchanged:
                break
            case .set(let projectID):
                schedule.projectID = projectID
            }
            schedule.modelHint = mutation.modelHint
            schedule.enabled = mutation.enabled
            schedule.updatedAt = .now
            try context.save()
            return id
        }

        return try create(
            name: mutation.name,
            kind: mutation.kind ?? .custom,
            cronExpression: mutation.cronExpression,
            prompt: mutation.prompt,
            threadID: mutation.threadID,
            projectID: mutation.projectID.valueForCreate,
            modelHint: mutation.modelHint,
            enabled: mutation.enabled
        )
    }

    public func allActive() throws -> [AgentSchedule] {
        try context.fetch(
            FetchDescriptor<AgentSchedule>(
                sortBy: [
                    SortDescriptor(\.name, order: .forward),
                    SortDescriptor(\.id, order: .forward),
                ]
            )
        )
    }

    public func setEnabled(_ enabled: Bool, id: UUID) throws {
        guard let schedule = try get(id: id) else { return }

        schedule.enabled = enabled
        schedule.updatedAt = .now
        try context.save()
    }

    public func touch(id: UUID, now: Date = .now) throws {
        guard let schedule = try get(id: id) else { return }

        schedule.updatedAt = now
        try context.save()
    }

    public func get(id: UUID) throws -> AgentSchedule? {
        try context.fetch(
            FetchDescriptor<AgentSchedule>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }
}

extension AgentScheduleOptionalFieldMutation {
    fileprivate var valueForCreate: Value? {
        switch self {
        case .unchanged:
            nil
        case .set(let value):
            value
        }
    }
}
