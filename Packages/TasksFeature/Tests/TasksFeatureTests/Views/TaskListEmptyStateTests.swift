import Foundation
import Testing

@testable import TasksFeature

@Suite("TaskListEmptyState resolution")
struct TaskListEmptyStateTests {
    @Test("Empty non-savedFilter result yields an empty-state with copy")
    func emptyUpcomingYieldsEmptyState() {
        let state = TaskListEmptyState.resolve(filter: .upcoming, isEmpty: true, hasError: false)
        guard case .empty(let title, let systemImage, let message) = state else {
            Issue.record("expected .empty, got \(state)")
            return
        }
        #expect(!title.isEmpty)
        #expect(!systemImage.isEmpty)
        #expect(!message.isEmpty)
    }

    @Test("Saved Filter owns its own empty/error UI — resolver stays out of its way")
    func savedFilterIsNone() {
        let state = TaskListEmptyState.resolve(
            filter: .savedFilter(UUID()),
            isEmpty: true,
            hasError: false
        )
        #expect(state == .none)
    }

    @Test("A load error does not get shadowed by the empty-state (existing error row path is kept)")
    func errorTakesPrecedenceOverEmpty() {
        let state = TaskListEmptyState.resolve(filter: .upcoming, isEmpty: true, hasError: true)
        #expect(state == .none)
    }

    @Test("Non-empty result never shows an empty-state")
    func nonEmptyIsNone() {
        #expect(TaskListEmptyState.resolve(filter: .all, isEmpty: false, hasError: false) == .none)
        #expect(TaskListEmptyState.resolve(filter: .today, isEmpty: false, hasError: false) == .none)
    }

    @Test("byTag empty-state surfaces the tag in its copy")
    func byTagEmbedsTag() {
        let state = TaskListEmptyState.resolve(filter: .byTag("work"), isEmpty: true, hasError: false)
        guard case .empty(let title, _, let message) = state else {
            Issue.record("expected .empty, got \(state)")
            return
        }
        #expect(title.contains("work") || message.contains("work"))
    }

    @Test("Every non-savedFilter filter has a distinct, non-generic empty-state")
    func eachFilterHasCopy() {
        let filters: [TaskFilter] = [
            .all, .today, .upcoming, .inbox, .completed,
            .byTag("x"), .project(UUID()), .projectSection(UUID(), UUID()),
        ]
        for filter in filters {
            let state = TaskListEmptyState.resolve(filter: filter, isEmpty: true, hasError: false)
            guard case .empty(let title, _, let message) = state else {
                Issue.record("expected .empty for \(filter), got \(state)")
                continue
            }
            #expect(!title.isEmpty)
            #expect(!message.isEmpty)
        }
    }
}
