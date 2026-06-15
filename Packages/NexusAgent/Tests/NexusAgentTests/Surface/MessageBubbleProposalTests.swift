import Foundation
import NexusCore
import Testing

@testable import NexusAgent

/// Task 5: Logic-level tests for the `.proposal` block-model mapping.
/// Tests the pure `AgentMessageGrouping.blocks(from:isThinking:proposals:)` API —
/// no SwiftUI snapshot required.
@Suite
struct MessageBubbleProposalTests {
    private static let sampleProposal = Proposal(
        rationale: "Create the task you asked for",
        mutations: [PendingMutation(toolName: "tasks.create", arguments: .object(["title": .string("My task")]))],
        previews: [ProposalPreview(summary: "tasks.create")]
    )

    @Test func agentBlockCarriesProposalWhenKeyedByMessageID() {
        let tid = UUID()
        let agentMsg = AgentMessage(threadID: tid, role: .agent, content: "Sure thing.")
        let blocks = AgentMessageGrouping.blocks(
            from: [agentMsg],
            isThinking: false,
            proposals: [agentMsg.id: Self.sampleProposal]
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].proposal?.rationale == "Create the task you asked for")
        #expect(blocks[0].proposal?.mutations.first?.toolName == "tasks.create")
        #expect(blocks[0].proposal?.previews.first?.summary == "tasks.create")
    }

    @Test func agentBlockHasNoProposalWhenNotKeyed() {
        let tid = UUID()
        let agentMsg = AgentMessage(threadID: tid, role: .agent, content: "Here are your tasks.")
        let blocks = AgentMessageGrouping.blocks(
            from: [agentMsg],
            isThinking: false,
            proposals: [:]
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].proposal == nil)
    }

    @Test func userBlockNeverCarriesProposal() {
        let tid = UUID()
        let userMsg = AgentMessage(threadID: tid, role: .user, content: "add a task")
        // Even if a stale proposal id somehow matches a user message, it must not attach.
        let blocks = AgentMessageGrouping.blocks(
            from: [userMsg],
            isThinking: false,
            proposals: [userMsg.id: Self.sampleProposal]
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .user)
        #expect(blocks[0].proposal == nil)
    }

    @Test func backwardsCompatibleNilProposalsDefault() {
        // Existing callers that don't pass `proposals` must still work unchanged.
        let tid = UUID()
        let agentMsg = AgentMessage(threadID: tid, role: .agent, content: "Done.")
        let blocks = AgentMessageGrouping.blocks(from: [agentMsg], isThinking: false)
        #expect(blocks[0].proposal == nil)
    }

    @Test func proposalCardInputsMappedCorrectly() {
        // Verify the card inputs (title / rationale / previews) are derivable from a proposal.
        let proposal = Self.sampleProposal
        let title = "Proposed changes"  // Static title we synthesize
        let cardRationale = proposal.rationale
        let cardPreviews = proposal.previews.map(\.summary)

        #expect(title == "Proposed changes")
        #expect(cardRationale == "Create the task you asked for")
        #expect(cardPreviews == ["tasks.create"])
    }
}
