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
    @Test("filters by tag")
    func filtersByTag() async throws {
        let tasks = [
            TaskItem(title: "Work item", tags: ["work"]),
            TaskItem(title: "Home item", tags: ["home"]),
        ]
        let fixture = try await InMemoryAgentContext.make(tasks: tasks)

        let response = try await callList(
            args: .object(["filter": .object(["tag": .string("work")])]),
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
    @Test("rejects reserved project id filter")
    func rejectsReservedProjectIDFilter() async throws {
        let task = TaskItem(title: "Unfiltered task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.validation("project_id filter is reserved until Projects land")) {
            _ = try await TasksListTool().call(
                args: .object(["filter": .object(["project_id": .string("project-1")])]),
                context: fixture.context
            )
        }
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

    private func callList(args: JSONValue, context: AgentContext) async throws -> TaskListResponseDTO {
        let result = try await TasksListTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskListResponseDTO.self, from: data)
    }
}
