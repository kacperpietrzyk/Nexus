import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct FoundationCompositionTests {
    // Trivial identity skill for wiring assertions.
    private struct Out: Sendable, Equatable { let value: String }

    @Test func factoryBuildsWithoutThrowingAndRunnerIsUsable() async throws {
        // Build the graph from all in-memory pieces.
        let graph = try FoundationComposition.makeForTesting()

        // Prove makeRunner() yields a live SkillRunner wired to the composed assembler.
        let inference = ScriptedSkillInference(responses: ["hello"])
        let runner = graph.makeRunner(inference: inference)

        let skill = AssistantSkill(
            id: "t",
            systemPrompt: "sys",
            contextRecipe: ContextRecipe(),
            output: OutputContract<Out>(schemaDescription: "{value:string}") { Out(value: $0) }
        )
        let runResult = try await runner.run(skill, focus: ContextFocus(), userText: "hi")
        #expect(runResult.output == Out(value: "hello"))
    }

    @Test func proposalCoordinatorAcceptsMutation() async throws {
        let graph = try FoundationComposition.makeForTesting()

        let mutation = PendingMutation(
            toolName: "tasks.create",
            arguments: .object(["title": .string("Wired task")])
        )
        let proposal = Proposal(
            rationale: "test",
            mutations: [mutation],
            previews: [ProposalPreview(summary: "Create: Wired task")]
        )
        let results = try await graph.proposalCoordinator.accept(proposal, threadID: nil)
        #expect(results.count == 1)
    }
}
