import Foundation
import NexusCore   // JSONValue

public struct PendingMutation: Sendable, Equatable {
    public let toolName: String
    public let arguments: JSONValue
    public init(toolName: String, arguments: JSONValue) { self.toolName = toolName; self.arguments = arguments }
}

public struct ProposalPreview: Sendable, Equatable {
    public let summary: String
    public init(summary: String) { self.summary = summary }
}

/// A bundle of pending mutations + rationale the UI renders as a confirm card.
/// In-memory only — never persisted (no schema change).
public struct Proposal: Sendable, Equatable {
    public let id: UUID
    public let rationale: String
    public let mutations: [PendingMutation]
    public let previews: [ProposalPreview]
    public init(id: UUID = UUID(), rationale: String, mutations: [PendingMutation], previews: [ProposalPreview]) {
        self.id = id; self.rationale = rationale; self.mutations = mutations; self.previews = previews
    }
}
