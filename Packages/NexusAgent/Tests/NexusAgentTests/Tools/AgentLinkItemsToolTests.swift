import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
struct AgentLinkItemsToolTests {
    @Test
    func linkItemsCreatesLinkRowWithRealEnumValues() async throws {
        let harness = try LinkToolHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)
        let fromID = try harness.insertLiveTask()
        let toID = UUID()

        let output = try await tool.call(
            args: Self.input(fromID: fromID, toID: toID, linkKind: "actionItem", order: 7),
            context: harness.agentContext
        )

        let object = try #require(output.objectValue)
        #expect(object["status"] == .string("ok"))
        #expect(UUID(uuidString: try #require(object["linkID"]?.stringValue)) != nil)
        #expect(object["idempotencyKey"]?.stringValue?.contains("actionItem") == true)

        let links = try harness.modelContext.fetch(FetchDescriptor<Link>())
        #expect(links.count == 1)
        let link = try #require(links.first)
        #expect(link.fromKind == .task)
        #expect(link.fromID == fromID)
        #expect(link.toKind == .agentMemory)
        #expect(link.toID == toID)
        #expect(link.linkKind == .actionItem)
        #expect(link.order == 7)
    }

    @Test
    func duplicateLinkItemsIsIdempotent() async throws {
        let harness = try LinkToolHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)
        let fromID = try harness.insertLiveTask()
        let toID = UUID()
        let input = Self.input(fromID: fromID, toID: toID, linkKind: "mentions")

        let first = try await tool.call(args: input, context: harness.agentContext)
        let second = try await tool.call(args: input, context: harness.agentContext)

        let links = try harness.modelContext.fetch(FetchDescriptor<Link>())
        #expect(links.count == 1)
        #expect(first.objectValue?["linkID"] == second.objectValue?["linkID"])
    }

    @Test
    func inverseHasUnlinkNameAndJSONValueCompatibleInput() async throws {
        let harness = try LinkToolHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)
        let input = Self.input(fromID: UUID(), toID: UUID(), linkKind: "source")

        let inverse = try await tool.inverse(input: input, context: harness.agentContext)

        #expect(inverse.toolName == "agent.unlink_items")
        #expect(try JSONDecoder().decode(JSONValue.self, from: inverse.inputJSON) == input)
    }

    @Test
    func undoingDuplicateLinkDispatchKeepsOriginalLink() async throws {
        let harness = try LinkToolHarness.make()
        let input = Self.input(fromID: try harness.insertLiveTask(), toID: UUID(), linkKind: "source")
        let threadID = UUID()

        let first = try await harness.dispatcher.dispatch(
            toolName: "agent.link_items",
            input: input,
            threadID: threadID,
            now: Date(timeIntervalSince1970: 1_800_000_001)
        )
        let second = try await harness.dispatcher.dispatch(
            toolName: "agent.link_items",
            input: input,
            threadID: threadID,
            now: Date(timeIntervalSince1970: 1_800_000_002)
        )

        #expect(first.output.objectValue?["linkID"] == second.output.objectValue?["linkID"])
        #expect(try harness.modelContext.fetch(FetchDescriptor<Link>()).count == 1)

        try await harness.coordinator.undo(
            auditLogID: second.auditLogID,
            now: Date(timeIntervalSince1970: 1_800_000_003)
        )

        let links = try harness.modelContext.fetch(FetchDescriptor<Link>())
        #expect(links.count == 1)
        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        let secondLog = try #require(logs.first { $0.id == second.auditLogID })
        #expect(secondLog.undoneAt != nil)
        #expect(logs.contains { $0.toolName == "agent.noop" && $0.threadID == threadID })
    }

    @Test
    func unlinkDeletesOnlyMatchingLinkAndReturnsCount() async throws {
        let harness = try LinkToolHarness.make()
        let linkTool = AgentLinkItemsTool(context: harness.modelContext)
        let unlinkTool = AgentUnlinkItemsTool(context: harness.modelContext)
        let fromID = try harness.insertLiveTask()
        let toID = UUID()
        let matchingInput = Self.input(fromID: fromID, toID: toID, linkKind: "blocks")
        let otherKindInput = Self.input(fromID: fromID, toID: toID, linkKind: "mentions")

        _ = try await linkTool.call(args: matchingInput, context: harness.agentContext)
        _ = try await linkTool.call(args: otherKindInput, context: harness.agentContext)

        let output = try await unlinkTool.call(args: matchingInput, context: harness.agentContext)

        #expect(output.objectValue?["status"] == .string("ok"))
        #expect(output.objectValue?["deletedCount"] == .int(1))
        let remaining = try harness.modelContext.fetch(FetchDescriptor<Link>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.linkKind == .mentions)
    }

    @Test
    func invalidEnumAndUUIDThrowValidationErrors() async throws {
        let harness = try LinkToolHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)

        await #expect(throws: AgentError.validation("Unknown fromKind: bogus")) {
            try await tool.call(
                args: .object([
                    "fromKind": .string("bogus"),
                    "fromID": .string(UUID().uuidString),
                    "toKind": .string("task"),
                    "toID": .string(UUID().uuidString),
                    "linkKind": .string("mentions"),
                ]),
                context: harness.agentContext
            )
        }

        await #expect(throws: AgentError.validation("toID must be a UUID string")) {
            try await tool.call(
                args: .object([
                    "fromKind": .string("task"),
                    "fromID": .string(UUID().uuidString),
                    "toKind": .string("task"),
                    "toID": .string("not-a-uuid"),
                    "linkKind": .string("mentions"),
                ]),
                context: harness.agentContext
            )
        }

        await #expect(throws: AgentError.validation("Unknown linkKind: refs")) {
            try await tool.call(
                args: .object([
                    "fromKind": .string("task"),
                    "fromID": .string(UUID().uuidString),
                    "toKind": .string("task"),
                    "toID": .string(UUID().uuidString),
                    "linkKind": .string("refs"),
                ]),
                context: harness.agentContext
            )
        }
    }

    private static func input(
        fromID: UUID,
        toID: UUID,
        linkKind: String,
        order: Int? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "fromKind": .string("task"),
            "fromID": .string(fromID.uuidString),
            "toKind": .string("agentMemory"),
            "toID": .string(toID.uuidString),
            "linkKind": .string(linkKind),
        ]
        if let order {
            object["order"] = .int(order)
        }
        return .object(object)
    }
}

@MainActor
private struct LinkToolHarness {
    let modelContext: ModelContext
    let agentContext: AgentContext
    let dispatcher: ToolDispatcher
    let coordinator: AgentUndoCoordinator

    /// `agent.link_items` now existence-checks both endpoints, so `.task`
    /// endpoints must be live rows (`.agentMemory` stays pass-through).
    func insertLiveTask() throws -> UUID {
        let task = TaskItem(title: "live endpoint")
        modelContext.insert(task)
        try modelContext.save()
        return task.id
    }

    static func make() throws -> LinkToolHarness {
        let schema = Schema([
            AgentAuditLog.self,
            AgentMemoryEntry.self,
            AgentMessage.self,
            AgentSchedule.self,
            AgentThread.self,
            DebugItem.self,
            ItemEmbedding.self,
            Link.self,
            QuotaLog.self,
            TaskItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let registry = ToolRegistry(tools: [
            AgentLinkItemsTool(context: modelContext),
            AgentUnlinkItemsTool(context: modelContext),
            AgentNoopTool(),
        ])
        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let dispatcher = ToolDispatcher(
            registry: registry,
            modelContext: modelContext,
            agentContext: agentContext
        )
        let coordinator = AgentUndoCoordinator(
            dispatcher: dispatcher,
            modelContext: modelContext
        )
        return LinkToolHarness(
            modelContext: modelContext,
            agentContext: agentContext,
            dispatcher: dispatcher,
            coordinator: coordinator
        )
    }
}
