import Foundation
import NexusAgentTools
import NexusCore

/// A tool whose execution mutates persisted state and therefore must
/// provide an `inverse(...)` so AgentUndoCoordinator can revert it.
public protocol MutatingAgentTool: AgentTool {
    @MainActor
    func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction
}
