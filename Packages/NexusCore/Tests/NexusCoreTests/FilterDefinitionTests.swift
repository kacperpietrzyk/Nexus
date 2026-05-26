import Foundation
import Testing

@testable import NexusCore

@Suite("FilterDefinition")
struct FilterDefinitionTests {
    @Test("basic filters match due deadline tag project section and boolean combinations")
    func basicFiltersMatchTaskFieldsAndCompositions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let projectID = UUID()
        let sectionID = UUID()
        let task = TaskItem(
            title: "Scoped",
            dueAt: now.addingTimeInterval(86_400),
            deadlineAt: now.addingTimeInterval(2 * 86_400),
            tags: ["phase-1i"],
            projectID: projectID,
            sectionID: sectionID
        )

        #expect(FilterDefinition.dueWithin(days: 2).matches(task, now: now, calendar: calendar))
        #expect(FilterDefinition.withDeadlineWithin(days: 3).matches(task, now: now, calendar: calendar))
        #expect(FilterDefinition.byTag("phase-1i").matches(task, now: now, calendar: calendar))
        #expect(FilterDefinition.byProject(projectID).matches(task, now: now, calendar: calendar))
        #expect(FilterDefinition.bySection(sectionID).matches(task, now: now, calendar: calendar))
        #expect(
            FilterDefinition
                .and([.byProject(projectID), .bySection(sectionID), .byTag("phase-1i")])
                .matches(task, now: now, calendar: calendar))
        #expect(
            FilterDefinition
                .or([.byTag("missing"), .withDeadlineWithin(days: 3)])
                .matches(task, now: now, calendar: calendar))
        #expect(!FilterDefinition.not(.byProject(projectID)).matches(task, now: now, calendar: calendar))
    }

    @Test("relative date filters reject missing and out-of-window dates")
    func relativeDateFiltersRejectMissingAndOutOfWindowDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let noDates = TaskItem(title: "No dates")
        let tooLate = TaskItem(
            title: "Later",
            dueAt: now.addingTimeInterval(4 * 86_400),
            deadlineAt: now.addingTimeInterval(5 * 86_400)
        )

        #expect(!FilterDefinition.dueWithin(days: 2).matches(noDates, now: now, calendar: calendar))
        #expect(!FilterDefinition.withDeadlineWithin(days: 3).matches(noDates, now: now, calendar: calendar))
        #expect(!FilterDefinition.dueWithin(days: 2).matches(tooLate, now: now, calendar: calendar))
        #expect(!FilterDefinition.withDeadlineWithin(days: 3).matches(tooLate, now: now, calendar: calendar))
    }

    @Test("priorityAtLeast matches equal and higher numeric priority values")
    func priorityAtLeastMatchesEqualAndHigherPriorities() {
        let filter = FilterDefinition.priorityAtLeast(.medium)

        #expect(!filter.matches(TaskItem(title: "none", priority: .none)))
        #expect(!filter.matches(TaskItem(title: "low", priority: .low)))
        #expect(filter.matches(TaskItem(title: "medium", priority: .medium)))
        #expect(filter.matches(TaskItem(title: "high", priority: .high)))
    }

    @Test("byTag canonicalizes filter and task tags")
    func byTagCanonicalizesFilterAndTaskTags() {
        let task = TaskItem(title: "Tagged", tags: [" Work "])

        #expect(FilterDefinition.byTag(" WORK ").matches(task))
        #expect(!FilterDefinition.byTag("home").matches(task))
    }

    @Test("normal filters do not match done snoozed or soft-deleted tasks")
    func normalFiltersOnlyMatchActiveOpenTasks() {
        let projectID = UUID()
        let done = TaskItem(title: "done", priority: .high, status: .done, tags: ["work"], projectID: projectID)
        let snoozed = TaskItem(title: "snoozed", priority: .high, status: .snoozed, tags: ["work"], projectID: projectID)
        let deleted = TaskItem(title: "deleted", priority: .high, tags: ["work"], projectID: projectID)
        deleted.deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let filters: [FilterDefinition] = [
            .byTag("work"),
            .byProject(projectID),
            .priorityAtLeast(.medium),
            .not(.byTag("missing")),
        ]

        for filter in filters {
            #expect(!filter.matches(done))
            #expect(!filter.matches(snoozed))
            #expect(!filter.matches(deleted))
        }
    }
}
