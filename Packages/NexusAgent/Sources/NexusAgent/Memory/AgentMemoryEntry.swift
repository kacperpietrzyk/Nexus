import Foundation
import NexusCore
import SwiftData

public enum AgentMemorySource: String, Codable, CaseIterable, Sendable {
    case user
    case agent
}

@Model
public final class AgentMemoryEntry: Searchable {
    public var id: UUID
    public var kindRaw: String
    public var scope: String
    public var key: String
    public var content: String
    public var sourceRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var confidence: Double
    public var linkedItemIDs: [UUID]

    public var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .agentMemory }
        set { kindRaw = newValue.rawValue }
    }

    public var title: String {
        get { key }
        set { key = newValue }
    }

    public var source: AgentMemorySource {
        get { AgentMemorySource(rawValue: sourceRaw) ?? .agent }
        set { sourceRaw = newValue.rawValue }
    }

    public var searchableText: String { "\(scope)\n\(key)\n\(content)" }

    public init(
        id: UUID = UUID(),
        scope: String = "global",
        key: String,
        content: String,
        source: AgentMemorySource = .agent,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        confidence: Double = 1.0,
        linkedItemIDs: [UUID] = []
    ) {
        self.id = id
        self.kindRaw = ItemKind.agentMemory.rawValue
        self.scope = scope
        self.key = key
        self.content = content
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.confidence = confidence
        self.linkedItemIDs = linkedItemIDs
    }
}
