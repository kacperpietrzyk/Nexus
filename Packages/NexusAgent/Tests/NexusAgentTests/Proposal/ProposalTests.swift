import Foundation
import NexusCore  // JSONValue
import Testing

@testable import NexusAgent

@Suite struct ProposalTests {
    @Test func proposalHoldsMutationsAndPreviews() {
        let m = PendingMutation(toolName: "tasks.create", arguments: .object(["title": .string("X")]))
        let p = Proposal(
            id: UUID(), rationale: "why", mutations: [m],
            previews: [ProposalPreview(summary: "Create task: X")])
        #expect(p.mutations.count == 1)
        #expect(p.mutations[0].toolName == "tasks.create")
        #expect(p.previews[0].summary == "Create task: X")
    }
}
