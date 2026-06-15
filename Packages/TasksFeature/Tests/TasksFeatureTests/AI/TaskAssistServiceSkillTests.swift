import Foundation
import NexusAI
import NexusAgent
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@MainActor
@Suite("TaskAssistService skill-backed proposal path")
struct TaskAssistServiceSkillTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TaskItem.self, Project.self, Person.self, Note.self, Link.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func makeRouter(responseText: String) -> AIRouter {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            isAvailableOnThisPlatform: true,
            responseText: responseText
        )
        return AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
    }

    @Test("refine title → Proposal with tasks.update mutation")
    func refineTitleProducesTasksUpdateProposal() async throws {
        let ctx = try makeContext()
        let task = TaskItem(title: "do the deploy thing")
        ctx.insert(task)
        let service = TaskAssistService(router: makeRouter(responseText: "Ship the Q3 deployment runbook"))
        let proposal = try await service.proposal(for: .refine(field: .title), on: task)
        #expect(proposal.mutations.count == 1)
        #expect(proposal.mutations[0].toolName == "tasks.update")
        guard case .object(let args) = proposal.mutations[0].arguments else {
            Issue.record("expected object args in tasks.update")
            return
        }
        guard case .object(let patch)? = args["patch"] else {
            Issue.record("expected patch object in tasks.update args")
            return
        }
        guard case .string(let refinedTitle)? = patch["title"] else {
            Issue.record("expected string title in patch")
            return
        }
        #expect(refinedTitle == "Ship the Q3 deployment runbook")
    }

    @Test("refine body → Proposal with tasks.update mutation (notes patch key)")
    func refineBodyProducesTasksUpdateProposal() async throws {
        let ctx = try makeContext()
        let task = TaskItem(title: "Write docs")
        ctx.insert(task)
        let service = TaskAssistService(router: makeRouter(responseText: "Document the API endpoints clearly."))
        let proposal = try await service.proposal(for: .refine(field: .body), on: task)
        #expect(proposal.mutations.count == 1)
        #expect(proposal.mutations[0].toolName == "tasks.update")
        guard case .object(let args) = proposal.mutations[0].arguments else {
            Issue.record("expected object args in tasks.update")
            return
        }
        guard case .object(let patch)? = args["patch"] else {
            Issue.record("expected patch object in tasks.update args")
            return
        }
        guard case .string(let notes)? = patch["notes"] else {
            Issue.record("expected string notes in patch")
            return
        }
        #expect(!notes.isEmpty)
    }

    @Test("breakIntoSubtasks → N tasks.create Proposals (not a silent write)")
    func breakdownProducesTasksCreateProposals() async throws {
        let ctx = try makeContext()
        let task = TaskItem(title: "Write the report")
        ctx.insert(task)
        let golden = #"{"subtasks":["Draft outline","Write section 1","Review"]}"#
        let service = TaskAssistService(router: makeRouter(responseText: golden))
        let proposal = try await service.proposal(for: .breakIntoSubtasks(maxCount: 5), on: task)
        #expect(proposal.mutations.count == 3)
        #expect(proposal.mutations.allSatisfy { $0.toolName == "tasks.create" })
        guard case .object(let args) = proposal.mutations[0].arguments else {
            Issue.record("expected object args in tasks.create")
            return
        }
        guard case .string(let parentID)? = args["parent_id"] else {
            Issue.record("expected parent_id in tasks.create args")
            return
        }
        #expect(parentID == task.id.uuidString)
    }

    @Test("suggestDueDate → Proposal with tasks.update and due_date patch key")
    func suggestDueDateProducesTasksUpdateWithDueDatePatch() async throws {
        let ctx = try makeContext()
        let task = TaskItem(title: "Plan offsite")
        ctx.insert(task)
        let golden = #"{"whenHint":"friday","estMinutes":30}"#
        let service = TaskAssistService(router: makeRouter(responseText: golden))
        let proposal = try await service.proposal(for: .suggestDueDate(now: .now), on: task)
        #expect(proposal.mutations.count == 1)
        #expect(proposal.mutations[0].toolName == "tasks.update")
        guard case .object(let args) = proposal.mutations[0].arguments else {
            Issue.record("expected object args in tasks.update")
            return
        }
        guard case .object(let patch)? = args["patch"] else {
            Issue.record("expected patch in tasks.update args")
            return
        }
        #expect(patch["due_date"] != nil)
    }

    @Test("existing run() API still works after adding proposal()")
    func existingRunAPIUnchanged() async throws {
        let service = TaskAssistService(router: makeRouter(responseText: "Improved title"))
        let task = TaskItem(title: "draft sloppy")
        let result = try await service.run(.refine(field: .title), on: task)
        guard case .refinedText(let text) = result else {
            Issue.record("Expected refinedText")
            return
        }
        #expect(text == "Improved title")
    }
}
