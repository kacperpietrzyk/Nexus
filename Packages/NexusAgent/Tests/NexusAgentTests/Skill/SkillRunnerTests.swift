import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct SkillRunnerTests {
    struct Out: Sendable, Equatable { let value: String }

    private func makeAssembler() throws -> ContextAssembler {
        let schema = Schema([TaskItem.self, Project.self, Person.self, Note.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let repo = TaskItemRepository(context: ctx, scheduler: RRuleScheduler(), now: { .now })
        let agentContext = AgentContext(
            modelContext: ModelContextRef(ctx),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: SearchIndex(),
            now: { .now })
        struct Empty: RagRetriever {
            func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
        }
        return ContextAssembler(agentContext: agentContext, retriever: Empty())
    }

    private func skill(decode: @escaping @Sendable (String) throws -> Out) -> AssistantSkill<Out> {
        AssistantSkill(
            id: "t",
            systemPrompt: "system",
            contextRecipe: ContextRecipe(),
            output: OutputContract<Out>(schemaDescription: "{value:string}", decode: decode))
    }

    @Test func validFirstTryReturnsDecodedOutputAndOneInferenceCall() async throws {
        let inference = ScriptedSkillInference(responses: ["hello"])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let result = try await runner.run(skill { Out(value: $0) }, focus: ContextFocus(), userText: "hi")
        #expect(result.output == Out(value: "hello"))
        #expect(inference.requests.count == 1)
        #expect(inference.requests[0].systemPrompt == "system")
    }

    @Test func malformedThenValidTriggersExactlyOneRetry() async throws {
        let inference = ScriptedSkillInference(responses: ["BAD", "good"])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let result = try await runner.run(
            skill { text in
                if text == "BAD" { throw OutputContractError.invalid(reason: "bad") }
                return Out(value: text)
            },
            focus: ContextFocus(), userText: "hi")
        #expect(result.output == Out(value: "good"))
        #expect(inference.requests.count == 2)
        // repair nudge present on the 2nd request
        #expect(inference.requests[1].prompt.contains("invalid"))
    }

    @Test func stillMalformedAfterRetryThrowsCleanly() async throws {
        let inference = ScriptedSkillInference(responses: ["BAD", "STILLBAD"])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        await #expect(throws: SkillRunError.self) {
            _ = try await runner.run(
                skill { _ in throw OutputContractError.invalid(reason: "bad") },
                focus: ContextFocus(), userText: "hi")
        }
        #expect(inference.requests.count == 2)  // one retry, then give up
    }

    @Test func iosStyleSkillSendsNoTools() async throws {
        let inference = ScriptedSkillInference(responses: ["ok"])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        _ = try await runner.run(skill { Out(value: $0) }, focus: ContextFocus(), userText: "hi")
        #expect(inference.requests[0].tools == nil)
    }

    // Tool-subset seam (spec §4.B) is deliberately unwired: even a skill that NAMES
    // tools sends `tools: nil`, because SkillRunner is single-shot and has no dispatch
    // loop. (allowsToolCalling is left false — the assert tripwire forbids true here.)
    @Test func namedToolsStillSendNilBecauseSeamIsUnwired() async throws {
        let inference = ScriptedSkillInference(responses: ["ok"])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let toolNamed = AssistantSkill<Out>(
            id: "t",
            systemPrompt: "system",
            toolNames: ["tasks.list", "search.global"],
            contextRecipe: ContextRecipe(),
            output: OutputContract<Out>(schemaDescription: "{value:string}", decode: { Out(value: $0) }))
        _ = try await runner.run(toolNamed, focus: ContextFocus(), userText: "hi")
        #expect(inference.requests[0].tools == nil)
    }
}
