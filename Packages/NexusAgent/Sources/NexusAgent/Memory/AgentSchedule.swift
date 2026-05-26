import Foundation
import SwiftData

public enum AgentScheduleKind: String, Codable, CaseIterable, Sendable {
    case builtIn = "built-in"
    case projectDigest = "project-digest"
    case custom
}

public enum AgentScheduleStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case success
    case failed
    case skipped
}

@Model
public final class AgentSchedule {
    public var id: UUID
    public var name: String
    public var kindRaw: String
    public var cronExpression: String
    public var prompt: String
    public var threadID: UUID?
    public var projectID: UUID?
    public var modelHint: String?
    public var enabled: Bool
    public var lastRunAt: Date?
    public var lastRunStatusRaw: String
    public var lastRunResultRef: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public var kind: AgentScheduleKind {
        get { AgentScheduleKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    public var lastRunStatus: AgentScheduleStatus {
        get { AgentScheduleStatus(rawValue: lastRunStatusRaw) ?? .pending }
        set { lastRunStatusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AgentScheduleKind = .builtIn,
        cronExpression: String,
        prompt: String,
        threadID: UUID? = nil,
        projectID: UUID? = nil,
        modelHint: String? = nil,
        enabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.cronExpression = cronExpression
        self.prompt = prompt
        self.threadID = threadID
        self.projectID = projectID
        self.modelHint = modelHint
        self.enabled = enabled
        self.lastRunAt = nil
        self.lastRunStatusRaw = AgentScheduleStatus.pending.rawValue
        self.lastRunResultRef = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
