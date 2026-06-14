import Foundation
import NexusAgent
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

/// Tests for Task 8: accepting / rejecting a Proposal through the audited ToolDispatcher.
///
/// The accept path goes through `TaskAssistActionHandler.accept(_:)` →
/// `FoundationComposition.makeLocalDispatcher` → `ProposalCoordinator.accept` →
/// `ToolDispatcher.dispatch` → `TasksUpdateTool.call` + `AgentAuditLog` insert.
@MainActor
@Suite("TaskAssistApplyTests")
struct TaskAssistApplyTests {
    // MARK: - Harness

    private struct ApplyHarness {
        let container: ModelContainer
        let context: ModelContext
        let repository: TaskItemRepository

        @MainActor
        static func make() throws -> ApplyHarness {
            // Full schema matching ProposalHarness so AgentAuditLog inserts succeed.
            let schema = Schema([
                AgentAuditLog.self,
                Link.self,
                DebugItem.self,
                QuotaLog.self,
                TaskItem.self,
                Project.self,
                Section.self,
                Comment.self,
                Note.self,
                ScheduledBlock.self,
                Label.self,
                Person.self,
                Cycle.self,
                ActivityEntry.self,
                SavedFilter.self,
                Organization.self,
                ProjectKeyDate.self,
            ])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            let repository = TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
            return ApplyHarness(container: container, context: context, repository: repository)
        }

        /// Re-fetch a TaskItem from a fresh context to avoid in-memory cache effects.
        func refetchTask(_ id: UUID) throws -> TaskItem? {
            let ctx = ModelContext(container)
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { t in t.id == id }
            )
            return try ctx.fetch(descriptor).first
        }

        func auditLogCount() throws -> Int {
            try context.fetch(FetchDescriptor<AgentAuditLog>()).count
        }
    }

    // MARK: - Helper: hand-build a refine Proposal for a known task

    private func makeRefineProposal(taskID: UUID, newTitle: String) -> Proposal {
        let args: JSONValue = .object([
            "task_id": .string(taskID.uuidString),
            "patch": .object(["title": .string(newTitle)]),
        ])
        return Proposal(
            rationale: "Refined title for clarity.",
            mutations: [PendingMutation(toolName: "tasks.update", arguments: args)],
            previews: [ProposalPreview(summary: "title: old → \(newTitle)")]
        )
    }

    // MARK: - Tests

    @Test("accepting a refine Proposal updates the TaskItem and writes an AgentAuditLog row")
    func acceptRefineProposalUpdatesTaskAndWritesAuditLog() async throws {
        let harness = try ApplyHarness.make()
        let task = TaskItem(title: "old title", body: "body")
        try harness.repository.insert(task)

        let proposal = makeRefineProposal(taskID: task.id, newTitle: "Refined title")
        let handler = TaskAssistActionHandler(task: task, router: nil, modelContext: harness.context)
        try await handler.accept(proposal)

        let updated = try harness.refetchTask(task.id)
        #expect(updated?.title == "Refined title")
        let auditCount = try harness.auditLogCount()
        #expect(auditCount == 1)
    }

    @Test("rejecting a Proposal writes no mutation and no AgentAuditLog row")
    func rejectProposalWritesNothingAndNoAuditLog() async throws {
        let harness = try ApplyHarness.make()
        let task = TaskItem(title: "original title", body: "body")
        try harness.repository.insert(task)

        let proposal = makeRefineProposal(taskID: task.id, newTitle: "Should not apply")

        // Rejection is modelled as simply not calling accept — no coordinator side-effects.
        // Directly assert that doing nothing leaves zero audit rows and title unchanged.
        let updated = try harness.refetchTask(task.id)
        #expect(updated?.title == "original title")
        let auditCount = try harness.auditLogCount()
        #expect(auditCount == 0)
        // Demonstrate ProposalCoordinator.reject is a no-op via the public API.
        let coordinator = FoundationComposition.makeLocalDispatcher(modelContext: harness.context)
        coordinator.reject(proposal)
        #expect(try harness.auditLogCount() == 0)
    }

    @Test("accept Proposal goes through ToolDispatcher (not direct write)")
    func acceptRoutesViaToolDispatcher() async throws {
        let harness = try ApplyHarness.make()
        let task = TaskItem(title: "draft", body: "")
        try harness.repository.insert(task)

        let proposal = makeRefineProposal(taskID: task.id, newTitle: "Shipped title")
        let handler = TaskAssistActionHandler(task: task, router: nil, modelContext: harness.context)
        let results = try await handler.accept(proposal)

        // ToolDispatcher returns one result per mutation; each carries an auditLogID.
        #expect(results.count == 1)
        #expect(results[0].auditLogID != UUID())
        // Verify the audit log ID actually exists in the store.
        let auditID = results[0].auditLogID
        let logs = try harness.context.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.contains { $0.id == auditID })
    }
}
