import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite
struct AgentRememberToolTests {
    @Test
    func rememberToolUpsertsEntryAndReturnsStatusAndID() async throws {
        let harness = try ToolTestHarness.make()
        let tool = AgentRememberTool(store: harness.store)

        let output = try await tool.call(
            args: .object([
                "scope": .string("global"),
                "key": .string("prefers-pl"),
                "content": .string("User prefers Polish responses"),
            ]),
            context: harness.agentContext
        )

        let object = try #require(output.objectValue)
        #expect(object["status"] == .string("ok"))
        let id = try #require(object["id"]?.stringValue)
        #expect(UUID(uuidString: id) != nil)
        #expect(
            try harness.store.find(scope: "global", key: "prefers-pl")?.content
                == "User prefers Polish responses"
        )
    }

    @Test
    func rememberToolInversePointsToForgetAndForgetDeletesEntry() async throws {
        let harness = try ToolTestHarness.make()
        let remember = AgentRememberTool(store: harness.store)
        let forget = AgentForgetTool(store: harness.store)
        let input: JSONValue = .object([
            "scope": .string("global"),
            "key": .string("k"),
            "content": .string("v"),
        ])

        let inverse = try await remember.inverse(input: input, context: harness.agentContext)
        _ = try await remember.call(args: input, context: harness.agentContext)

        #expect(inverse.toolName == "agent.forget")
        let forgetInput = try JSONDecoder().decode(JSONValue.self, from: inverse.inputJSON)
        #expect(
            forgetInput
                == .object([
                    "scope": .string("global"),
                    "key": .string("k"),
                ])
        )

        _ = try await forget.call(args: forgetInput, context: harness.agentContext)
        #expect(try harness.store.find(scope: "global", key: "k") == nil)
    }

    @Test
    func rememberToolInverseRestoresExistingEntry() async throws {
        let harness = try ToolTestHarness.make()
        let remember = AgentRememberTool(store: harness.store)
        let linkedID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        _ = try harness.store.upsert(
            scope: "global",
            key: "preference",
            content: "old content",
            confidence: 0.25,
            linkedItemIDs: [linkedID]
        )
        let updateInput: JSONValue = .object([
            "scope": .string("global"),
            "key": .string("preference"),
            "content": .string("new content"),
            "confidence": .double(0.9),
            "linkedItemIDs": .array([]),
        ])

        let inverse = try await remember.inverse(input: updateInput, context: harness.agentContext)
        _ = try await remember.call(args: updateInput, context: harness.agentContext)
        let restoreInput = try JSONDecoder().decode(JSONValue.self, from: inverse.inputJSON)
        _ = try await remember.call(args: restoreInput, context: harness.agentContext)

        #expect(inverse.toolName == "agent.remember")
        let restored = try #require(try harness.store.find(scope: "global", key: "preference"))
        #expect(restored.content == "old content")
        #expect(restored.confidence == 0.25)
        #expect(restored.linkedItemIDs == [linkedID])
    }

    @Test
    func rememberToolUpdatesSameScopeKeyWithoutDuplicating() async throws {
        let harness = try ToolTestHarness.make()
        let tool = AgentRememberTool(store: harness.store)
        let firstInput: JSONValue = .object([
            "scope": .string("global"),
            "key": .string("preference"),
            "content": .string("v1"),
        ])
        let secondInput: JSONValue = .object([
            "scope": .string("global"),
            "key": .string("preference"),
            "content": .string("v2"),
            "confidence": .double(0.75),
        ])

        _ = try await tool.call(args: firstInput, context: harness.agentContext)
        _ = try await tool.call(args: secondInput, context: harness.agentContext)

        let entries = try harness.store.list(scope: "global")
        #expect(entries.count == 1)
        #expect(entries.first?.content == "v2")
        #expect(entries.first?.confidence == 0.75)
    }

    @Test
    func rememberToolRejectsMissingRequiredField() async throws {
        let harness = try ToolTestHarness.make()
        let tool = AgentRememberTool(store: harness.store)

        await #expect(throws: AgentError.validation("Missing required string field: content")) {
            try await tool.call(
                args: .object([
                    "scope": .string("global"),
                    "key": .string("preference"),
                ]),
                context: harness.agentContext
            )
        }
    }

    @Test
    func forgetToolRejectsMissingRequiredField() async throws {
        let harness = try ToolTestHarness.make()
        let tool = AgentForgetTool(store: harness.store)

        await #expect(throws: AgentError.validation("Missing required string field: key")) {
            try await tool.call(
                args: .object(["scope": .string("global")]),
                context: harness.agentContext
            )
        }
    }
}

@MainActor
struct ToolTestHarness {
    let store: AgentMemoryStore
    let agentContext: AgentContext

    static func make() throws -> ToolTestHarness {
        let context = try AgentTestSupport.makeContext()
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return ToolTestHarness(
            store: AgentMemoryStore(context: context),
            agentContext: AgentContext(
                modelContext: ModelContextRef(context),
                taskRepository: TaskItemRepositoryRef(repository),
                searchIndex: SearchIndex(),
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
        )
    }
}
