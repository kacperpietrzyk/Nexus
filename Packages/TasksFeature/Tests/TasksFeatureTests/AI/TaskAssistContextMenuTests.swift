import Foundation
import NexusAI
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

struct TaskAssistContextMenuTests {
    @Test("typed assist errors map to actionable UI copy")
    func assistErrorCopyIsActionable() {
        let title = TaskAssistErrorCopy.message(
            for: TaskAssistService.AssistError.emptyRefinement(.title)
        )
        let invalidDate = TaskAssistErrorCopy.message(
            for: TaskAssistService.AssistError.invalidDateFormat("tomorrow")
        )
        let pastDate = TaskAssistErrorCopy.message(
            for: TaskAssistService.AssistError.pastDueDate(.distantPast, now: .now)
        )

        #expect(title.contains("empty title"))
        #expect(title.contains("try again"))
        #expect(invalidDate.contains("usable due date"))
        #expect(invalidDate.contains("timing hint"))
        #expect(pastDate.contains("past due date"))
        #expect(pastDate.contains("future timing hint"))
    }

    @Test("router errors explain local-only AI path")
    func routerErrorCopyMentionsLocalOnlyAIPath() {
        let consent = TaskAssistErrorCopy.message(
            for: AIRouterError.consentRequired(.appleIntelligence)
        )
        let quota = TaskAssistErrorCopy.message(
            for: AIRouterError.quotaExceeded(.whisperKit)
        )
        let requestFailed = TaskAssistErrorCopy.message(
            for: AIRouterError.requestFailed(.appleIntelligence, "lookup failed")
        )
        let unsupported = TaskAssistErrorCopy.message(
            for: AIRouterError.capabilityNotSupported(.generate)
        )
        let notImplemented = TaskAssistErrorCopy.message(
            for: AIRouterError.providerNotImplemented(.appleIntelligence)
        )

        #expect(consent.contains("Apple Intelligence"))
        #expect(consent.contains("AI settings"))
        #expect(quota.contains("WhisperKit"))
        #expect(quota.contains("quota"))
        #expect(!quota.contains("another provider"))
        #expect(requestFailed.contains("Apple Intelligence"))
        #expect(requestFailed.contains("Try again"))
        #expect(unsupported.contains("local generation capability"))
        #expect(!unsupported.contains("another provider"))
        #expect(notImplemented.contains("Phase 1l"))
        #expect(!notImplemented.contains("another provider"))
    }

    @Test("local UI errors are not raw enum descriptions")
    func localUIErrorCopyIsHumanReadable() {
        let noRouter = TaskAssistErrorCopy.message(for: TaskAssistUIError.aiUnavailable)
        let noRepo = TaskAssistErrorCopy.message(for: TaskAssistUIError.repositoryUnavailable)
        let emptySubtasks = TaskAssistErrorCopy.message(for: TaskAssistUIError.emptySubtasks)

        #expect(noRouter.contains("AI is not available"))
        #expect(noRepo.contains("task storage is not available"))
        #expect(emptySubtasks.contains("usable subtasks"))
    }

    @MainActor
    @Test("refine title updates task and persists through repository")
    func refineTitlePersistsThroughRepository() async throws {
        let harness = try makeHarness()
        let task = TaskItem(title: "draft title", body: "body")
        try harness.repository.insert(task)

        try await TaskAssistActionHandler(
            task: task,
            router: makeRouter(responseText: "  Sharper title  "),
            modelContext: harness.context,
            repository: harness.repository
        ).perform(.refineTitle)

        let stored = try fetchTask(task.id, in: harness.container)
        #expect(stored.title == "Sharper title")
        #expect(stored.body == "body")
        #expect(stored.updatedAt == harness.stamp)
    }

    @MainActor
    @Test("refine body updates task and persists through model context fallback")
    func refineBodyPersistsThroughModelContextFallback() async throws {
        let harness = try makeHarness()
        let task = TaskItem(title: "title", body: "rough notes")
        harness.context.insert(task)
        try harness.context.save()

        try await TaskAssistActionHandler(
            task: task,
            router: makeRouter(responseText: "\nClear body copy\n"),
            modelContext: harness.context,
            repository: nil
        ).perform(.refineBody)

        let stored = try fetchTask(task.id, in: harness.container)
        #expect(stored.title == "title")
        #expect(stored.body == "Clear body copy")
    }

    @MainActor
    @Test("suggest due date writes dueAt without touching deadlineAt")
    func suggestDueDateWritesDueAtOnly() async throws {
        let harness = try makeHarness()
        let deadline = try #require(ISO8601DateFormatter().date(from: "2030-06-20T00:00:00Z"))
        let suggestedDue = try #require(ISO8601DateFormatter().date(from: "2030-06-15T10:00:00Z"))
        let task = TaskItem(title: "Plan offsite", deadlineAt: deadline)
        try harness.repository.insert(task)

        try await TaskAssistActionHandler(
            task: task,
            router: makeRouter(responseText: "2030-06-15T10:00:00Z"),
            modelContext: harness.context,
            repository: harness.repository
        ).perform(.suggestDueDate)

        let stored = try fetchTask(task.id, in: harness.container)
        #expect(stored.dueAt == suggestedDue)
        #expect(stored.deadlineAt == deadline)
    }

    @MainActor
    @Test("suggest due date preserves timed task duration")
    func suggestDueDatePreservesTimedTaskDuration() async throws {
        let harness = try makeHarness()
        let originalDue = try #require(ISO8601DateFormatter().date(from: "2030-06-14T00:00:00Z"))
        let originalStart = try #require(ISO8601DateFormatter().date(from: "2030-06-14T09:30:00Z"))
        let originalEnd = try #require(ISO8601DateFormatter().date(from: "2030-06-14T11:00:00Z"))
        let suggestedDue = try #require(ISO8601DateFormatter().date(from: "2030-06-15T13:15:00Z"))
        let expectedEnd = try #require(ISO8601DateFormatter().date(from: "2030-06-15T14:45:00Z"))
        let task = TaskItem(
            title: "Plan offsite",
            dueAt: originalDue,
            startAt: originalStart,
            endAt: originalEnd
        )
        try harness.repository.insert(task)

        try await TaskAssistActionHandler(
            task: task,
            router: makeRouter(responseText: "2030-06-15T13:15:00Z"),
            modelContext: harness.context,
            repository: harness.repository
        ).perform(.suggestDueDate)

        let stored = try fetchTask(task.id, in: harness.container)
        #expect(stored.dueAt == suggestedDue)
        #expect(stored.startAt == suggestedDue)
        #expect(stored.endAt == expectedEnd)
    }

    @MainActor
    @Test("suggest due date clears invalid timed task end")
    func suggestDueDateClearsInvalidTimedTaskEnd() async throws {
        let harness = try makeHarness()
        let originalStart = try #require(ISO8601DateFormatter().date(from: "2030-06-14T09:30:00Z"))
        let invalidEnd = try #require(ISO8601DateFormatter().date(from: "2030-06-14T09:00:00Z"))
        let suggestedDue = try #require(ISO8601DateFormatter().date(from: "2030-06-15T13:15:00Z"))
        let task = TaskItem(
            title: "Plan offsite",
            startAt: originalStart,
            endAt: invalidEnd
        )
        try harness.repository.insert(task)

        try await TaskAssistActionHandler(
            task: task,
            router: makeRouter(responseText: "2030-06-15T13:15:00Z"),
            modelContext: harness.context,
            repository: harness.repository
        ).perform(.suggestDueDate)

        let stored = try fetchTask(task.id, in: harness.container)
        #expect(stored.dueAt == suggestedDue)
        #expect(stored.startAt == suggestedDue)
        #expect(stored.endAt == nil)
    }

    @MainActor
    @Test("suggest due date clears absent timed task end")
    func suggestDueDateClearsAbsentTimedTaskEnd() async throws {
        let harness = try makeHarness()
        let originalStart = try #require(ISO8601DateFormatter().date(from: "2030-06-14T09:30:00Z"))
        let suggestedDue = try #require(ISO8601DateFormatter().date(from: "2030-06-15T13:15:00Z"))
        let task = TaskItem(title: "Plan offsite", startAt: originalStart, endAt: nil)
        try harness.repository.insert(task)

        try await TaskAssistActionHandler(
            task: task,
            router: makeRouter(responseText: "2030-06-15T13:15:00Z"),
            modelContext: harness.context,
            repository: harness.repository
        ).perform(.suggestDueDate)

        let stored = try fetchTask(task.id, in: harness.container)
        #expect(stored.dueAt == suggestedDue)
        #expect(stored.startAt == suggestedDue)
        #expect(stored.endAt == nil)
    }

    @MainActor
    @Test("menu actions expose busy state and perform selected action")
    func menuActionsPerformSelectedAction() {
        var performedAction: TaskAssistUIAction?
        let idleActions = TaskAssistMenuActions(inFlightAction: nil) { action in
            performedAction = action
        }
        let busyActions = TaskAssistMenuActions(inFlightAction: .refineTitle) { _ in }

        #expect(idleActions.isBusy == false)
        idleActions.perform(.suggestDueDate)
        #expect(performedAction == .suggestDueDate)
        #expect(busyActions.isBusy)
    }

    @MainActor
    @Test("break into subtasks creates children preserving parent assignment")
    func breakIntoSubtasksCreatesChildrenWithParentAssignment() async throws {
        let harness = try makeHarness()
        let projectID = UUID()
        let sectionID = UUID()
        let parent = TaskItem(title: "Ship release", projectID: projectID, sectionID: sectionID)
        try harness.repository.insert(parent)

        try await TaskAssistActionHandler(
            task: parent,
            router: makeRouter(
                responseText: """
                    - Draft release notes
                    - Build archive
                    """
            ),
            modelContext: harness.context,
            repository: harness.repository
        ).perform(.breakIntoSubtasks)

        let children = try fetchTasks(in: harness.container)
            .filter { $0.parentTaskID == parent.id }
            .sorted { $0.title < $1.title }
        #expect(children.map(\.title) == ["Build archive", "Draft release notes"])
        #expect(children.allSatisfy { $0.projectID == projectID })
        #expect(children.allSatisfy { $0.sectionID == sectionID })
    }

    @MainActor
    @Test("break into subtasks without repository throws repositoryUnavailable")
    func breakIntoSubtasksWithoutRepositoryThrows() async throws {
        let harness = try makeHarness()
        let provider = FakeAIProvider(id: .appleIntelligence, responseText: "Child")
        let task = TaskItem(title: "Parent")
        harness.context.insert(task)
        try harness.context.save()

        do {
            try await TaskAssistActionHandler(
                task: task,
                router: makeRouter(provider: provider),
                modelContext: harness.context,
                repository: nil
            ).perform(.breakIntoSubtasks)
            Issue.record("Expected repositoryUnavailable error")
        } catch TaskAssistUIError.repositoryUnavailable {
            #expect(provider.generateCallCount == 0)
        } catch {
            Issue.record("Expected repositoryUnavailable, got \(error)")
        }
    }

    @MainActor
    @Test("break into subtasks propagates done parent guard")
    func breakIntoSubtasksPropagatesDoneParentGuard() async throws {
        let harness = try makeHarness()
        let parent = TaskItem(title: "Already done", status: .done)
        try harness.repository.insert(parent)

        do {
            try await TaskAssistActionHandler(
                task: parent,
                router: makeRouter(responseText: "Child task"),
                modelContext: harness.context,
                repository: harness.repository
            ).perform(.breakIntoSubtasks)
            Issue.record("Expected parentNotOpen error")
        } catch TaskSubtaskActionError.parentNotOpen(let parentID) {
            #expect(parentID == parent.id)
        } catch {
            Issue.record("Expected parentNotOpen, got \(error)")
        }
    }
}

@MainActor
private func makeHarness(
    stamp: Date = Date(timeIntervalSinceReferenceDate: 913_000)
) throws -> TaskAssistHarness {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: TaskItem.self, configurations: config)
    let context = container.mainContext
    let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
    return TaskAssistHarness(container: container, context: context, repository: repository, stamp: stamp)
}

@MainActor
private func fetchTask(_ id: UUID, in container: ModelContainer) throws -> TaskItem {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<TaskItem>(
        predicate: #Predicate { task in
            task.id == id
        }
    )
    return try #require(context.fetch(descriptor).first)
}

@MainActor
private func fetchTasks(in container: ModelContainer) throws -> [TaskItem] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<TaskItem>())
}

private func makeRouter(responseText: String) -> AIRouter {
    let provider = FakeAIProvider(
        id: .appleIntelligence,
        capabilities: [.generate],
        isAvailableOnThisPlatform: true,
        responseText: responseText
    )
    return makeRouter(provider: provider)
}

private func makeRouter(provider: any AIProvider) -> AIRouter {
    return AIRouter(
        providers: [provider],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )
}

private struct TaskAssistHarness {
    let container: ModelContainer
    let context: ModelContext
    let repository: TaskItemRepository
    let stamp: Date
}
