import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct AgentAuditViewModelTests {
    @Test func auditViewModelLoadsRecentEntries() throws {
        let harness = try AgentAuditHarness.make()
        for index in 0..<3 {
            harness.context.insert(
                AgentAuditLog(
                    timestamp: Date(timeIntervalSince1970: 1_777_000_000 + Double(index)),
                    toolName: "noop.\(index)",
                    inputJSON: Data(),
                    outputJSON: Data()
                )
            )
        }
        try harness.context.save()

        let viewModel = AgentAuditViewModel(
            context: harness.context,
            undoCoordinator: harness.undoCoordinator
        )

        #expect(viewModel.entries.count == 3)
        #expect(viewModel.entries.first?.toolName == "noop.2")
    }

    @Test func reloadLimitsToOneHundredNewestEntries() throws {
        let harness = try AgentAuditHarness.make()
        for index in 0..<120 {
            harness.context.insert(
                AgentAuditLog(
                    timestamp: Date(timeIntervalSince1970: 1_777_000_000 + Double(index)),
                    toolName: "noop.\(index)",
                    inputJSON: Data(),
                    outputJSON: Data()
                )
            )
        }
        try harness.context.save()

        let viewModel = AgentAuditViewModel(
            context: harness.context,
            undoCoordinator: harness.undoCoordinator
        )

        #expect(viewModel.entries.count == 100)
        #expect(viewModel.entries.first?.toolName == "noop.119")
        #expect(viewModel.entries.last?.toolName == "noop.20")
    }

    @Test func undoFailureResetsUndoingStateAndReloads() async throws {
        let harness = try AgentAuditHarness.make()
        let logID = UUID()
        harness.context.insert(
            AgentAuditLog(
                id: logID,
                toolName: "readonly",
                inputJSON: Data(),
                outputJSON: Data()
            )
        )
        try harness.context.save()
        let viewModel = AgentAuditViewModel(
            context: harness.context,
            undoCoordinator: harness.undoCoordinator
        )

        await viewModel.undo(id: logID)

        #expect(viewModel.isUndoing == false)
        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries.first?.id == logID)
    }
}

@MainActor
private struct AgentAuditHarness {
    let context: ModelContext
    let undoCoordinator: AgentUndoCoordinator

    static func make() throws -> AgentAuditHarness {
        let schema = Schema([
            AgentAuditLog.self,
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
        let context = ModelContext(container)
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(context),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let registry = ToolRegistry(tools: [])
        let dispatcher = ToolDispatcher(
            registry: registry,
            modelContext: context,
            agentContext: agentContext
        )
        let undoCoordinator = AgentUndoCoordinator(
            registry: registry,
            dispatcher: dispatcher,
            context: context
        )
        return AgentAuditHarness(context: context, undoCoordinator: undoCoordinator)
    }
}
