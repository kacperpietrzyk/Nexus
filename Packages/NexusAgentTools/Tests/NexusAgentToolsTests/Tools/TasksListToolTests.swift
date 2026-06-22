import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("TasksListTool")
struct TasksListToolTests {
    @MainActor
    @Test("default filter returns open non-deleted tasks")
    func defaultFilterReturnsOpenTasks() async throws {
        let tasks = [
            TaskItem(title: "Open 1"),
            TaskItem(title: "Open 2"),
            TaskItem(title: "Done", status: .done),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(args: .object([:]), context: fixture.context)

        #expect(response.total == 2)
        #expect(response.tasks.map(\.title) == ["Open 2", "Open 1"])
        #expect(response.tasks.allSatisfy { $0.state == "open" })
    }

    @MainActor
    @Test("filters by done state")
    func filtersDoneState() async throws {
        let tasks = [
            TaskItem(title: "Open"),
            TaskItem(title: "Done", status: .done),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(
            args: .object(["filter": .object(["state": .string("done")])]),
            context: fixture.context
        )

        #expect(response.total == 1)
        #expect(response.tasks.first?.title == "Done")
        #expect(response.tasks.first?.state == "done")
    }

    @MainActor
    @Test("state any includes deleted and snoozed tasks")
    func stateAnyIncludesDeletedAndSnoozedTasks() async throws {
        let open = TaskItem(title: "Open")
        let snoozed = TaskItem(title: "Snoozed", status: .snoozed)
        snoozed.snoozedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        let deleted = TaskItem(title: "Deleted")
        deleted.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [open, snoozed, deleted])

        let response = try await callList(
            args: .object(["filter": .object(["state": .string("any")])]),
            context: fixture.context
        )

        #expect(response.total == 3)
        #expect(Set(response.tasks.map(\.state)) == ["open", "deleted"])
        #expect(response.tasks.contains { $0.title == "Snoozed" && $0.snoozeUntil != nil })
    }

    @MainActor
    @Test("pagination reports total and has_more")
    func pagination() async throws {
        let tasks = (0..<5).map { index in
            TaskItem(title: "Task \(index)")
        }
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(
            args: .object(["limit": .int(2)]),
            context: fixture.context
        )

        #expect(response.tasks.count == 2)
        #expect(response.total == 5)
        #expect(response.hasMore)
    }

    @MainActor
    @Test("filters by tag using core tag canonicalization")
    func filtersByTagUsingCoreCanonicalization() async throws {
        let tasks = [
            TaskItem(title: "Work item", tags: [" Work "]),
            TaskItem(title: "Home item", tags: ["home"]),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(
            args: .object(["filter": .object(["tag": .string("WORK")])]),
            context: fixture.context
        )

        #expect(response.total == 1)
        #expect(response.tasks.first?.title == "Work item")
    }

    @MainActor
    @Test("rejects non-object filter")
    func rejectsNonObjectFilter() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("filter must be an object")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .string("today")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects invalid sort type and enum")
    func rejectsInvalidSortTypeAndEnum() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("sort must be a string")) {
            _ = try await TasksListTool().call(
                args: .object(["sort": .int(1)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("Invalid sort")) {
            _ = try await TasksListTool().call(
                args: .object(["sort": .string("updated")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects empty tag filter")
    func rejectsEmptyTagFilter() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("filter.tag cannot be empty")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["tag": .string("  \n")])]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects malformed project_id filter")
    func rejectsMalformedProjectIDFilter() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("filter.project_id must be a valid UUID")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["project_id": .string("not-a-uuid")])]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects malformed richer filters")
    func rejectsMalformedRicherFilters() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("filter.overdue must be a boolean")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["overdue": .string("yes")])]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("filter.deadline_within must be an integer")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["deadline_within": .string("soon")])]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("filter.deadline_within must be >= 1")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["deadline_within": .int(0)])]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("filter.priority_at_least must be an integer from 1 to 4")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["priority_at_least": .string("high")])]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("filters by project_id")
    func filtersByProject() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Work")
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        let inProject = TaskItem(title: "in project")
        let outOfProject = TaskItem(title: "out of project")
        try fixture.repo.insert(inProject)
        try fixture.repo.insert(outOfProject)
        try fixture.repo.assign(inProject, toProject: project.id, section: nil)

        let response = try await callList(
            args: .object(["filter": .object(["project_id": .string(project.id.uuidString)])]),
            context: fixture.context
        )

        #expect(response.total == 1)
        #expect(response.tasks.map(\.title) == ["in project"])
    }

    @MainActor
    @Test("filters by section_id")
    func filtersBySection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Work")
        let targetSection = Section(projectID: project.id, name: "Doing")
        let otherSection = Section(projectID: project.id, name: "Later")
        fixture.repo.context.insert(project)
        fixture.repo.context.insert(targetSection)
        fixture.repo.context.insert(otherSection)
        try fixture.repo.context.save()

        let inSection = TaskItem(title: "in section", tags: ["doing"])
        let inOtherSection = TaskItem(title: "in other section", tags: ["doing"])
        let unsectioned = TaskItem(title: "unsectioned", tags: ["doing"])
        try fixture.repo.insert(inSection)
        try fixture.repo.insert(inOtherSection)
        try fixture.repo.insert(unsectioned)
        try fixture.repo.assign(inSection, toProject: project.id, section: targetSection.id)
        try fixture.repo.assign(inOtherSection, toProject: project.id, section: otherSection.id)
        try fixture.repo.assign(unsectioned, toProject: project.id, section: nil)

        let response = try await callList(
            args: .object(["filter": .object(["section_id": .string(targetSection.id.uuidString)])]),
            context: fixture.context
        )

        #expect(response.total == 1)
        #expect(response.tasks.map(\.title) == ["in section"])
        #expect(response.tasks.first?.sectionID == targetSection.id.uuidString)
    }

    @MainActor
    @Test("filters by overdue")
    func filtersByOverdue() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let tomorrow = now.addingTimeInterval(86_400)
        let tasks = [
            TaskItem(title: "Overdue", dueAt: yesterday),
            TaskItem(title: "Future", dueAt: tomorrow),
            TaskItem(title: "No due"),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks, now: { now })

        let response = try await callList(
            args: .object(["filter": .object(["overdue": .bool(true)])]),
            context: fixture.context
        )

        #expect(response.total == 1)
        #expect(response.tasks.map(\.title) == ["Overdue"])
    }

    @MainActor
    @Test("filters by priority_at_least")
    func filtersByPriorityAtLeast() async throws {
        let high = TaskItem(title: "High")
        high.priorityRaw = TaskPriority.high.rawValue
        let medium = TaskItem(title: "Medium")
        medium.priorityRaw = TaskPriority.medium.rawValue
        let low = TaskItem(title: "Low")
        low.priorityRaw = TaskPriority.low.rawValue
        let none = TaskItem(title: "None")
        none.priorityRaw = TaskPriority.none.rawValue

        let fixture = try await InMemoryAgentContext.make(tasks: [high, medium, low, none])

        // MCP priority_at_least: 2 = "medium or better" → returns high + medium
        let response = try await callList(
            args: .object(["filter": .object(["priority_at_least": .int(2)])]),
            context: fixture.context
        )

        #expect(response.total == 2)
        #expect(Set(response.tasks.map(\.title)) == ["High", "Medium"])
    }

    @MainActor
    @Test("deadline_within matches core filter semantics")
    func deadlineWithinMatchesCoreFilterSemantics() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let overdue = TaskItem(title: "Overdue deadline")
        overdue.deadlineAt = now.addingTimeInterval(-86_400)
        let inWindow = TaskItem(title: "In window")
        inWindow.deadlineAt = now.addingTimeInterval(2 * 86_400)
        let beyondWindow = TaskItem(title: "Beyond window")
        beyondWindow.deadlineAt = now.addingTimeInterval(5 * 86_400)
        let fixture = try await InMemoryAgentContext.make(
            tasks: [overdue, inWindow, beyondWindow],
            now: { now }
        )

        let response = try await callList(
            args: .object(["filter": .object(["deadline_within": .int(3)])]),
            context: fixture.context
        )

        #expect(response.total == 2)
        #expect(Set(response.tasks.map(\.title)) == ["Overdue deadline", "In window"])
    }

    @MainActor
    @Test("project filter works with state=any")
    func projectFilterWorksWithStateAny() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Mixed")
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        let openTask = TaskItem(title: "Open in project")
        let doneTask = TaskItem(title: "Done in project", status: .done)
        let outTask = TaskItem(title: "Open out of project")
        try fixture.repo.insert(openTask)
        try fixture.repo.insert(doneTask)
        try fixture.repo.insert(outTask)
        try fixture.repo.assign(openTask, toProject: project.id, section: nil)
        try fixture.repo.assign(doneTask, toProject: project.id, section: nil)

        let response = try await callList(
            args: .object([
                "filter": .object([
                    "project_id": .string(project.id.uuidString),
                    "state": .string("any"),
                ])
            ]),
            context: fixture.context
        )

        #expect(response.total == 2)
        #expect(Set(response.tasks.map(\.title)) == ["Open in project", "Done in project"])
    }

    @MainActor
    @Test("excludes soft-deleted by default")
    func excludesSoftDeletedByDefault() async throws {
        let live = TaskItem(title: "Live")
        let deleted = TaskItem(title: "Deleted")
        deleted.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [live, deleted])

        let response = try await callList(args: .object([:]), context: fixture.context)

        #expect(response.total == 1)
        #expect(response.tasks.first?.title == "Live")
    }

    @MainActor
    @Test("open state excludes snoozed tasks")
    func openExcludesSnoozed() async throws {
        let open = TaskItem(title: "Open")
        let snoozed = TaskItem(title: "Snoozed", status: .snoozed)
        snoozed.snoozedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await InMemoryAgentContext.make(tasks: [open, snoozed])

        let response = try await callList(args: .object([:]), context: fixture.context)

        #expect(response.total == 1)
        #expect(response.tasks.first?.state == "open")
    }

    @MainActor
    @Test("upcoming excludes later today and includes tomorrow")
    func upcomingStartsTomorrow() async throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 12)))
        let startOfToday = calendar.startOfDay(for: now)
        let laterToday = try #require(calendar.date(byAdding: .hour, value: 18, to: startOfToday))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: startOfToday))
        let tomorrowMorning = try #require(calendar.date(byAdding: .hour, value: 9, to: tomorrow))
        let tasks = [
            TaskItem(title: "Later today", dueAt: laterToday),
            TaskItem(title: "Tomorrow", dueAt: tomorrowMorning),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks, now: { now })

        let response = try await callList(
            args: .object(["filter": .object(["bucket": .string("upcoming")])]),
            context: fixture.context
        )

        #expect(response.total == 1)
        #expect(response.tasks.map(\.title) == ["Tomorrow"])
    }

    @MainActor
    @Test("templates are excluded by default")
    func templatesExcludedByDefault() async throws {
        let tasks = [
            TaskItem(title: "Live"),
            TaskItem(title: "Template", isTemplate: true),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(args: .object([:]), context: fixture.context)

        #expect(response.total == 1)
        #expect(response.tasks.map(\.title) == ["Live"])
    }

    @MainActor
    @Test("include_templates opts templates in")
    func includeTemplatesOptsIn() async throws {
        let tasks = [
            TaskItem(title: "Live"),
            TaskItem(title: "Template", isTemplate: true),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(
            args: .object(["filter": .object(["include_templates": .bool(true)])]),
            context: fixture.context
        )

        #expect(response.total == 2)
    }

    @MainActor
    @Test("unfiled bucket returns open, done, and snoozed unassigned tasks but not assigned or soft-deleted")
    func unfiledBucketReturnsLiveUnassignedAnyState() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = Project(name: "Work")
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        let unassignedOpen = TaskItem(title: "Unassigned Open")
        let unassignedDone = TaskItem(title: "Unassigned Done", status: .done)
        let unassignedSnoozed = TaskItem(title: "Unassigned Snoozed", status: .snoozed)
        unassignedSnoozed.snoozedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        let unassignedDeleted = TaskItem(title: "Unassigned Deleted")
        unassignedDeleted.deletedAt = Date()
        let assigned = TaskItem(title: "Assigned")

        try fixture.repo.insert(unassignedOpen)
        try fixture.repo.insert(unassignedDone)
        try fixture.repo.insert(unassignedSnoozed)
        try fixture.repo.insert(unassignedDeleted)
        try fixture.repo.insert(assigned)
        try fixture.repo.assign(assigned, toProject: project.id, section: nil)

        let response = try await callList(
            args: .object(["filter": .object(["bucket": .string("unfiled")])]),
            context: fixture.context
        )

        #expect(response.total == 3)
        let titles = Set(response.tasks.map(\.title))
        #expect(titles == ["Unassigned Open", "Unassigned Done", "Unassigned Snoozed"])
        #expect(!titles.contains("Assigned"))
        #expect(!titles.contains("Unassigned Deleted"))
    }

    private func callList(args: JSONValue, context: AgentContext) async throws -> TaskListResponseDTO {
        let result = try await TasksListTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskListResponseDTO.self, from: data)
    }
}

/// `sort=created` chronology coverage: the comparator coalesces
/// `occurredAt ?? createdAt`, so a back-dated event date wins over the
/// record-creation timestamp. A separate suite to keep the main struct inside
/// the type-body lint budget.
@Suite("TasksListTool sort=created occurred_at")
struct TasksListToolCreatedSortTests {
    @MainActor
    @Test("sort=created orders by occurredAt when set, else createdAt")
    func sortCreatedCoalescesOccurredAt() async throws {
        // `early` was created LAST (latest createdAt) but carries an EARLY
        // occurredAt → it must sort as the OLDEST event (last, descending order).
        let early = TaskItem(title: "Early event, late record")
        early.createdAt = Date(timeIntervalSince1970: 3_000)
        early.occurredAt = Date(timeIntervalSince1970: 1_000)

        // `late` has no occurredAt → coalesces to its createdAt (newest event).
        let late = TaskItem(title: "No event date")
        late.createdAt = Date(timeIntervalSince1970: 2_000)

        let fixture = try await InMemoryAgentContext.make(tasks: [early, late])

        let response = try await callList(
            args: .object(["sort": .string("created")]),
            context: fixture.context
        )

        // Descending by event date: late (2000) before early (1000).
        #expect(response.tasks.map(\.title) == ["No event date", "Early event, late record"])
    }

    @MainActor
    @Test("sort=created falls back to createdAt for nil occurredAt rows")
    func sortCreatedNilFallsBackToCreatedAt() async throws {
        let older = TaskItem(title: "Older")
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = TaskItem(title: "Newer")
        newer.createdAt = Date(timeIntervalSince1970: 2_000)

        let fixture = try await InMemoryAgentContext.make(tasks: [older, newer])

        let response = try await callList(
            args: .object(["sort": .string("created")]),
            context: fixture.context
        )

        #expect(response.tasks.map(\.title) == ["Newer", "Older"])
    }

    private func callList(args: JSONValue, context: AgentContext) async throws -> TaskListResponseDTO {
        let result = try await TasksListTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskListResponseDTO.self, from: data)
    }
}
