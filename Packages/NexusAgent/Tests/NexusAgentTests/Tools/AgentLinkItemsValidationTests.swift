import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

/// `agent.link_items` endpoint validation (Tranche 2, Plan A review follow-up):
/// the registered production tool must run BOTH endpoints through
/// `AgentEndpointValidator.validateLive` before `LinkRepository.findOrCreate`,
/// so a hallucinated or soft-deleted `.cycle`/`.project`/`.label`/`.task` id
/// never mints a dangling edge (A2) — the same guard the NexusAgentTools edge
/// tools (`note.link`, `blocks.add`, …) already enforce.
@MainActor
struct AgentLinkItemsValidationTests {
    @Test("link_items rejects a hallucinated cycle endpoint instead of minting a dangling edge (A2)")
    func linkItemsRejectsHallucinatedCycle() async throws {
        let harness = try ValidationHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)
        let task = harness.insertTask(title: "anchor")

        await #expect(throws: AgentError.self) {
            _ = try await tool.call(
                args: Self.input(
                    fromKind: "task", fromID: task.id,
                    toKind: "cycle", toID: UUID(),
                    linkKind: "mentions"
                ),
                context: harness.agentContext
            )
        }
        #expect(try harness.modelContext.fetch(FetchDescriptor<Link>()).isEmpty)
    }

    @Test("link_items accepts live endpoints and rejects after cycle soft-delete")
    func linkItemsAcceptsLiveCycleRejectsSoftDeleted() async throws {
        let harness = try ValidationHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)
        let task = harness.insertTask(title: "anchor")
        let cycle = Cycle(name: "Sprint 1", startAt: .now, endAt: .now)
        harness.modelContext.insert(cycle)
        try harness.modelContext.save()

        // Live cycle -> link is created.
        let output = try await tool.call(
            args: Self.input(
                fromKind: "task", fromID: task.id,
                toKind: "cycle", toID: cycle.id,
                linkKind: "mentions"
            ),
            context: harness.agentContext
        )
        #expect(output.objectValue?["status"] == .string("ok"))
        #expect(try harness.modelContext.fetch(FetchDescriptor<Link>()).count == 1)

        // Soft-deleted cycle -> rejected (dangling id reads as "no cycle").
        cycle.deletedAt = .now
        try harness.modelContext.save()
        await #expect(throws: AgentError.self) {
            _ = try await tool.call(
                args: Self.input(
                    fromKind: "task", fromID: task.id,
                    toKind: "cycle", toID: cycle.id,
                    linkKind: "blocks"
                ),
                context: harness.agentContext
            )
        }
        #expect(try harness.modelContext.fetch(FetchDescriptor<Link>()).count == 1)
    }

    @Test("link_items validates the FROM endpoint too (hallucinated task rejected)")
    func linkItemsRejectsHallucinatedFromTask() async throws {
        let harness = try ValidationHarness.make()
        let tool = AgentLinkItemsTool(context: harness.modelContext)

        await #expect(throws: AgentError.self) {
            _ = try await tool.call(
                args: Self.input(
                    fromKind: "task", fromID: UUID(),
                    toKind: "agentMemory", toID: UUID(),
                    linkKind: "mentions"
                ),
                context: harness.agentContext
            )
        }
        #expect(try harness.modelContext.fetch(FetchDescriptor<Link>()).isEmpty)
    }

    private static func input(
        fromKind: String, fromID: UUID,
        toKind: String, toID: UUID,
        linkKind: String
    ) -> JSONValue {
        .object([
            "fromKind": .string(fromKind),
            "fromID": .string(fromID.uuidString),
            "toKind": .string(toKind),
            "toID": .string(toID.uuidString),
            "linkKind": .string(linkKind),
        ])
    }
}

@MainActor
private struct ValidationHarness {
    let modelContext: ModelContext
    let agentContext: AgentContext

    func insertTask(title: String) -> TaskItem {
        let task = TaskItem(title: title)
        modelContext.insert(task)
        try? modelContext.save()
        return task
    }

    static func make() throws -> ValidationHarness {
        let schema = Schema([
            AgentMemoryEntry.self,
            Cycle.self,
            DebugItem.self,
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
        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return ValidationHarness(modelContext: modelContext, agentContext: agentContext)
    }
}
