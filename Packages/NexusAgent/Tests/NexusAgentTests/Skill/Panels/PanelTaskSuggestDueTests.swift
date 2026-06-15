import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct PanelTaskSuggestDueTests {
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

    @Test func suggestDueResolvesViaDateMathNotModel() async throws {
        let golden = #"{"whenHint":"friday","estMinutes":30}"#
        let inference = ScriptedSkillInference(responses: [golden])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let resolved = Date(timeIntervalSince1970: 1_800_500_000)
        struct Fixed: DateExtracting {
            let d: Date
            func date(from hint: String, now: Date, locale: Locale) async -> Date? { d }
        }
        let coordinator = PanelTaskSuggestDueCoordinator(
            runner: runner, dateMath: DateMath(extractor: Fixed(d: resolved)))
        let proposal = try await coordinator.suggestDue(
            taskID: UUID(), title: "x", focus: ContextFocus(), now: .now)
        #expect(proposal.mutations.count == 1)
        guard case .object(let a) = proposal.mutations[0].arguments else {
            Issue.record("expected object args")
            return
        }
        guard case .object(let patch)? = a["patch"] else {
            Issue.record("expected patch object")
            return
        }
        guard case .string(let due)? = patch["due_date"] else {
            Issue.record("expected due_date string")
            return
        }
        #expect(due == ISO8601DateFormatter().string(from: resolved))
    }

    @Test func suggestDueFallsBackToTomorrowWhenExtractorReturnsNil() async throws {
        let golden = #"{"whenHint":"someday","estMinutes":0}"#
        let inference = ScriptedSkillInference(responses: [golden])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        struct NilExtractor: DateExtracting {
            func date(from hint: String, now: Date, locale: Locale) async -> Date? { nil }
        }
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = PanelTaskSuggestDueCoordinator(
            runner: runner, dateMath: DateMath(calendar: .current, extractor: NilExtractor()))
        let proposal = try await coordinator.suggestDue(
            taskID: UUID(), title: "later task", focus: ContextFocus(), now: fixedNow)
        #expect(proposal.mutations.count == 1)
        guard case .object(let a) = proposal.mutations[0].arguments else {
            Issue.record("expected object args")
            return
        }
        guard case .object(let patch)? = a["patch"] else {
            Issue.record("expected patch object")
            return
        }
        guard case .string(let due)? = patch["due_date"] else {
            Issue.record("expected due_date string")
            return
        }
        let dateMath = DateMath()
        let expectedDate = dateMath.startOfDay(dateMath.addDays(1, to: fixedNow))
        #expect(due == ISO8601DateFormatter().string(from: expectedDate))
    }
}
