import Foundation
import NexusAI
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

// NOTE(Task 8): The direct-write tests (refineTitlePersistsThroughRepository,
// refineBodyPersistsThroughModelContextFallback, all suggestDueDate* variants,
// breakIntoSubtasks*) were removed when the direct-apply paths were replaced with
// propose-confirm via ToolDispatcher. The equivalent accept-path coverage lives in
// TaskAssistApplyTests.swift. Copy/mapping tests remain here.

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

    @Test("action labels map to service actions")
    func actionLabelsMapToServiceActions() {
        #expect(TaskAssistUIAction.refineTitle.serviceAction == .refine(field: .title))
        #expect(TaskAssistUIAction.refineBody.serviceAction == .refine(field: .body))
        #expect(TaskAssistUIAction.breakIntoSubtasks.serviceAction == .breakIntoSubtasks())
    }
}
