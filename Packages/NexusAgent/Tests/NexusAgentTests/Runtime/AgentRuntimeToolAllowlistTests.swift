import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

// Tests that AgentTurnRequest.toolAllowlist restricts both the flat-prompt
// toolDefinitionsJSON (ContextBuilder) and the structured AIRequest.tools
// surface (makeAIRequest), so the model physically cannot see write tools.

@MainActor
@Suite(.serialized)
struct AgentRuntimeToolAllowlistTests {
    // A minimal stub tool used exclusively in this suite.
    private struct ListTool: AgentTool {
        let name = "tasks.list"
        let description = "List tasks."
        let inputSchema: JSONSchema = .object(properties: [:], required: [])
        func call(args: JSONValue, context: AgentContext) async throws -> JSONValue { .null }
    }

    private struct CreateTool: AgentTool {
        let name = "tasks.create"
        let description = "Create a task."
        let inputSchema: JSONSchema = .object(properties: [:], required: [])
        func call(args: JSONValue, context: AgentContext) async throws -> JSONValue { .null }
    }

    // MARK: - ContextBuilder direct (toolDefinitionsJSON surface)

    @Test func allowlistFiltersToolDefinitionsJSON() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let builder = ContextBuilder(
            memoryStore: AgentMemoryStore(context: ctx),
            messageStore: AgentMessageStore(context: ctx),
            retriever: NoopRetriever(),
            tools: [ListTool(), CreateTool()]
        )

        let window = try await builder.build(
            threadID: UUID(),
            scope: "global",
            userPrompt: "hi",
            toolAllowlist: ["tasks.list"]
        )

        let tools = try #require(
            JSONSerialization.jsonObject(with: window.toolDefinitionsJSON) as? [[String: Any]]
        )
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names == ["tasks.list"])
        #expect(!names.contains("tasks.create"))
    }

    @Test func nilAllowlistRetainsAllToolsInDefinitionsJSON() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let builder = ContextBuilder(
            memoryStore: AgentMemoryStore(context: ctx),
            messageStore: AgentMessageStore(context: ctx),
            retriever: NoopRetriever(),
            tools: [ListTool(), CreateTool()]
        )

        let window = try await builder.build(
            threadID: UUID(),
            scope: "global",
            userPrompt: "hi",
            toolAllowlist: nil
        )

        let tools = try #require(
            JSONSerialization.jsonObject(with: window.toolDefinitionsJSON) as? [[String: Any]]
        )
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names.contains("tasks.list"))
        #expect(names.contains("tasks.create"))
    }

    // MARK: - Runtime (AIRequest.tools surface — the critical structured path)

    @Test func allowlistFiltersProviderReceivedToolSpecs() async throws {
        let harness = try RuntimeHarness.make(
            tools: [ListTool(), CreateTool()],
            scripts: [.text("done")]
        )
        let threadID = try harness.threadStore.create(title: "allowlist-filter")

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "list tasks",
                scope: "global",
                toolAllowlist: ["tasks.list"]
            )
        )

        let received = harness.provider.lastToolSpecs
        let names = Set(received.map(\.name))
        #expect(names.isSubset(of: ["tasks.list"]))
        #expect(!names.contains("tasks.create"))
    }

    @Test func nilAllowlistPassesAllToolSpecsToProvider() async throws {
        let harness = try RuntimeHarness.make(
            tools: [ListTool(), CreateTool()],
            scripts: [.text("done")]
        )
        let threadID = try harness.threadStore.create(title: "allowlist-nil")

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "list tasks",
                scope: "global",
                toolAllowlist: nil
            )
        )

        let received = harness.provider.lastToolSpecs
        let names = Set(received.map(\.name))
        #expect(names.contains("tasks.list"))
        #expect(names.contains("tasks.create"))
    }
}

private struct NoopRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
}
