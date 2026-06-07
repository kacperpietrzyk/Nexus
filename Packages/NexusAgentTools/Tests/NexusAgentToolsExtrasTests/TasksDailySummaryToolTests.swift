import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentToolsExtras

@Suite("TasksDailySummaryTool")
struct TasksDailySummaryToolTests {
    @MainActor
    @Test("returns hero brief, today, upcoming, and focus buckets")
    func summary() async throws {
        let now = makeDate(year: 2026, month: 5, day: 6, hour: 9)
        let todayMorning = makeDate(year: 2026, month: 5, day: 6, hour: 10)
        let todayAfternoon = makeDate(year: 2026, month: 5, day: 6, hour: 14)
        let todayEvening = makeDate(year: 2026, month: 5, day: 6, hour: 20)
        let tomorrow = makeDate(year: 2026, month: 5, day: 7, hour: 11)
        let deleted = TaskItem(title: "Deleted", dueAt: todayMorning)
        deleted.deletedAt = now
        let done = TaskItem(title: "Done", dueAt: todayMorning, status: .done)
        let fixture = try await InMemoryAgentContextWithExtras.make(
            tasks: [
                TaskItem(title: "Morning review", dueAt: todayMorning),
                TaskItem(title: "Afternoon call", dueAt: todayAfternoon),
                TaskItem(title: "Evening plan", dueAt: todayEvening),
                TaskItem(title: "Tomorrow follow-up", dueAt: tomorrow),
                TaskItem(title: "Inbox idea"),
                deleted,
                done,
            ],
            now: { now }
        )

        let dto = try await callSummary(context: fixture.context)

        #expect(dto.heroBrief == "Today: 3 due, 0 overdue, 1 inbox")
        #expect(dto.today.map(\.title) == ["Morning review", "Afternoon call", "Evening plan"])
        #expect(dto.upcoming.map(\.title) == ["Tomorrow follow-up"])
        #expect(dto.focusBuckets.am.map(\.title) == ["Morning review"])
        #expect(dto.focusBuckets.pm.map(\.title) == ["Afternoon call"])
        #expect(dto.focusBuckets.evening.map(\.title) == ["Evening plan"])
    }

    @MainActor
    @Test("uses optional date argument as summary day")
    func dateArgument() async throws {
        let now = makeDate(year: 2026, month: 5, day: 6, hour: 9)
        let requestedDay = makeDate(year: 2026, month: 5, day: 8, hour: 10)
        let fixture = try await InMemoryAgentContextWithExtras.make(
            tasks: [
                TaskItem(title: "Today", dueAt: now),
                TaskItem(title: "Requested", dueAt: requestedDay),
                TaskItem(title: "Later", dueAt: makeDate(year: 2026, month: 5, day: 9, hour: 10)),
            ],
            now: { now }
        )

        let dto = try await callSummary(
            args: .object(["date": .string("2026-05-08")]),
            context: fixture.context
        )

        #expect(dto.heroBrief == "Today: 1 due, 1 overdue, 0 inbox")
        #expect(dto.today.map(\.title) == ["Today", "Requested"])
        #expect(dto.upcoming.map(\.title) == ["Later"])
    }

    @MainActor
    @Test("throws validation for malformed date")
    func invalidDate() async throws {
        let fixture = try await InMemoryAgentContextWithExtras.make()

        await #expect(throws: AgentError.validation("date must be YYYY-MM-DD")) {
            _ = try await TasksDailySummaryTool().call(
                args: .object(["date": .string("2026-02-31")]),
                context: fixture.context
            )
        }
        await #expect(throws: AgentError.validation("date must be YYYY-MM-DD")) {
            _ = try await TasksDailySummaryTool().call(
                args: .object(["date": .int(2_026)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("throws internal error when hero brief service is not wired")
    func missingHeroBriefService() async throws {
        let base = try await InMemoryAgentContextWithExtras.make()
        let context = AgentContext(
            modelContext: base.context.modelContext,
            taskRepository: base.context.taskRepository,
            searchIndex: base.context.searchIndex,
            now: base.context.now,
            nlParser: base.context.nlParser
        )

        await #expect(throws: AgentError.internalError("tasks.daily_summary requires a hero brief service")) {
            _ = try await TasksDailySummaryTool().call(args: .object([:]), context: context)
        }
    }

    @Test("extras registration includes core and extras tools")
    func registration() {
        let names = AgentToolsAll.tools().map(\.name)

        #expect(names.count == 22)
        #expect(Set(names).count == names.count)
        #expect(names.contains("tasks.create_from_text"))
        #expect(names.contains("tasks.daily_summary"))
        #expect(names.contains("note.create"))
    }

    @Test("extras-only registration does not include core task tools")
    func extrasOnlyRegistration() {
        let names = NexusAgentToolsExtras.tools().map(\.name)

        #expect(names == ["tasks.create_from_text", "tasks.daily_summary"])
        #expect(Set(names).count == names.count)
    }

    @MainActor
    private func callSummary(args: JSONValue = .object([:]), context: AgentContext) async throws -> DailySummaryDTO {
        let result = try await TasksDailySummaryTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(DailySummaryDTO.self, from: data)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
