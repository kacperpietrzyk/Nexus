// Packages/NexusAgent/Tests/NexusAgentTests/ProposalCodableTests.swift
import Foundation
import Testing
import NexusCore
@testable import NexusAgent

@Suite struct ProposalCodableTests {
    @Test func roundTrips() throws {
        let proposal = Proposal(
            id: UUID(),
            rationale: "Reschedule overdue",
            mutations: [PendingMutation(toolName: "tasks.update", arguments: .object(["id": .string("x")]))],
            previews: [ProposalPreview(summary: "Move 3 tasks to today")]
        )
        let data = try JSONEncoder().encode(proposal)
        let decoded = try JSONDecoder().decode(Proposal.self, from: data)
        #expect(decoded == proposal)
    }
}
