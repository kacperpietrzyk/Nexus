import Foundation

@MainActor
public final class ProposalCoordinator {
    private let dispatcher: ToolDispatcher
    public init(dispatcher: ToolDispatcher) { self.dispatcher = dispatcher }

    /// Apply every pending mutation through the existing audited dispatcher.
    /// Returns the dispatch results (each carries an auditLogID for undo via AgentUndoCoordinator).
    @discardableResult
    public func accept(_ proposal: Proposal, threadID: UUID?) async throws -> [ToolDispatchResult] {
        var results: [ToolDispatchResult] = []
        for mutation in proposal.mutations {
            let result = try await dispatcher.dispatch(toolName: mutation.toolName, input: mutation.arguments, threadID: threadID)
            results.append(result)
        }
        return results
    }

    /// Discard — zero side effects.
    public func reject(_ proposal: Proposal) { /* intentionally empty */  }
}
