import Foundation
import NexusAI
import NexusAgent
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@MainActor
@Suite("HeroBriefService skill path")
struct HeroBriefServiceSkillTests {
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

    @Test("ready + model text → returns model sentence")
    func readyPathReturnsModelText() async throws {
        let ctx = try makeContext()
        let router = makeRouter(responseText: "You have 3 tasks due and 0 overdue.")
        let readyProbe: @MainActor @Sendable () -> AssistantReadiness = { .ready }
        let skillPath: @MainActor @Sendable (String, Date) async throws -> String = { summary, date in
            let runner = FoundationComposition.makeLocalRunner(modelContext: ctx, router: router)
            return try await PanelDailyBriefCoordinator(runner: runner)
                .brief(summaryNumbers: summary, focus: ContextFocus(), now: date)
        }
        let service = HeroBriefService(
            router: router,
            skillPath: skillPath,
            readinessProbe: readyProbe
        )
        let counts = HeroBriefService.Counts(overdue: 0, today: 3, noDate: 0, awaiting: 0)
        let result = await service.brief(for: counts, firstTitles: ["Task A"], now: .now)
        #expect(result == "You have 3 tasks due and 0 overdue.")
    }

    @Test("not-ready → skill path is skipped (zero skill path invocations)")
    func notReadySkipsSkillPath() async throws {
        let ctx = try makeContext()
        // A router that always throws — so if the skill path runs anyway it would also fail,
        // but the key assertion is that the skill path closure is never called.
        let noProviderRouter = AIRouter(
            providers: [],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        let notReadyProbe: @MainActor @Sendable () -> AssistantReadiness = { .notDownloaded }
        var skillInvoked = false
        let skillPath: @MainActor @Sendable (String, Date) async throws -> String = { _, _ in
            skillInvoked = true
            let runner = FoundationComposition.makeLocalRunner(
                modelContext: ctx, router: noProviderRouter)
            return try await PanelDailyBriefCoordinator(runner: runner)
                .brief(summaryNumbers: "", focus: ContextFocus(), now: .now)
        }
        let service = HeroBriefService(
            router: noProviderRouter,
            skillPath: skillPath,
            readinessProbe: notReadyProbe
        )
        let counts = HeroBriefService.Counts(overdue: 0, today: 2, noDate: 0, awaiting: 0)
        let result = await service.brief(for: counts, firstTitles: [], now: .now)
        // Not-ready → skill path must not be called
        #expect(skillInvoked == false)
        // Falls through to legacyQuery → router throws → deterministic template
        #expect(result.contains("Everything else has been quietly set aside."))
    }

    @Test("skill error → deterministic fallback (known subtitle)")
    func skillErrorFallsBackToTemplate() async throws {
        let ctx = try makeContext()
        // Empty response → OutputContract throws → SkillRunError → fallback
        let router = makeRouter(responseText: "")
        let readyProbe: @MainActor @Sendable () -> AssistantReadiness = { .ready }
        let skillPath: @MainActor @Sendable (String, Date) async throws -> String = { summary, date in
            let runner = FoundationComposition.makeLocalRunner(modelContext: ctx, router: router)
            return try await PanelDailyBriefCoordinator(runner: runner)
                .brief(summaryNumbers: summary, focus: ContextFocus(), now: date)
        }
        let service = HeroBriefService(
            router: router,
            skillPath: skillPath,
            readinessProbe: readyProbe
        )
        let counts = HeroBriefService.Counts(overdue: 1, today: 0, noDate: 0, awaiting: 0)
        let result = await service.brief(for: counts, firstTitles: [], now: .now)
        #expect(result.contains("Everything else has been quietly set aside."))
    }

    @Test("cache: identical key within TTL returns same value without new inference call")
    func cachePreventsReInference() async throws {
        let ctx = try makeContext()
        var callCount = 0
        let router = makeRouter(responseText: "Cached sentence.")
        let readyProbe: @MainActor @Sendable () -> AssistantReadiness = { .ready }
        let skillPath: @MainActor @Sendable (String, Date) async throws -> String = { summary, date in
            callCount += 1
            let runner = FoundationComposition.makeLocalRunner(modelContext: ctx, router: router)
            return try await PanelDailyBriefCoordinator(runner: runner)
                .brief(summaryNumbers: summary, focus: ContextFocus(), now: date)
        }
        let service = HeroBriefService(
            router: router,
            ttl: 1800,
            skillPath: skillPath,
            readinessProbe: readyProbe
        )
        let counts = HeroBriefService.Counts(overdue: 0, today: 1, noDate: 0, awaiting: 0)
        let now = Date.now
        let first = await service.brief(for: counts, firstTitles: [], now: now)
        let second = await service.brief(for: counts, firstTitles: [], now: now.addingTimeInterval(10))
        #expect(first == second)
        // Only one inference call (the second was served from cache)
        #expect(callCount == 1)
    }
}
