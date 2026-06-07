import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("Calendar events agent tools")
struct CalendarEventsToolsTests {
    private static let now = Date(timeIntervalSince1970: 1_700_038_800)
    private static func clock() -> Date { now }

    private func iso(_ offset: TimeInterval) -> String {
        ScheduleDTOFormatter.string(Self.now.addingTimeInterval(offset))
    }

    // MARK: - list

    @MainActor
    @Test("calendar.events.list returns events overlapping the window")
    func listReturnsEvents() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let event = CalendarEvent(
            id: "e1",
            title: "Standup",
            start: Self.now,
            end: Self.now.addingTimeInterval(1800)
        )
        let provider = FakeCalendarProvider(stubEvents: [event])

        let result = try await CalendarEventsListTool(provider: provider).call(
            args: .object(["start": .string(iso(-3600)), "end": .string(iso(3600))]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([CalendarEventDTO].self, from: result)
        #expect(dtos.map(\.title) == ["Standup"])
    }

    @MainActor
    @Test("calendar.events.list throws when access not granted")
    func listRequiresAccess() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider(status: .denied)
        await #expect(throws: AgentError.self) {
            _ = try await CalendarEventsListTool(provider: provider).call(
                args: .object(["start": .string(iso(0)), "end": .string(iso(3600))]),
                context: fixture.context
            )
        }
    }

    // MARK: - create (idempotent)

    @MainActor
    @Test("calendar.events.create creates in the Nexus calendar by default")
    func createDefaultsToNexusCalendar() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()

        let result = try await CalendarEventsCreateTool(writer: provider).call(
            args: .object([
                "title": .string("Focus block"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(CalendarEventDTO.self, from: result)
        #expect(dto.title == "Focus block")
        #expect(dto.calendarID == "nexus-cal")
        #expect(provider.createdDrafts.count == 1)
    }

    @MainActor
    @Test("calendar.events.create is idempotent on identical title/start/end")
    func createIdempotent() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        let args = JSONValue.object([
            "title": .string("Focus block"),
            "start": .string(iso(0)),
            "end": .string(iso(3600)),
        ])

        let first = try await CalendarEventsCreateTool(writer: provider).call(args: args, context: fixture.context)
        let second = try await CalendarEventsCreateTool(writer: provider).call(args: args, context: fixture.context)

        let firstDTO = try TasksToolJSON.decode(CalendarEventDTO.self, from: first)
        let secondDTO = try TasksToolJSON.decode(CalendarEventDTO.self, from: second)
        #expect(firstDTO.id == secondDTO.id)  // reused, not duplicated
        #expect(provider.createdDrafts.count == 1)  // only one write
    }

    @MainActor
    @Test("calendar.events.create rejects end <= start")
    func createRejectsBadRange() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        await #expect(throws: AgentError.self) {
            _ = try await CalendarEventsCreateTool(writer: provider).call(
                args: .object([
                    "title": .string("bad"),
                    "start": .string(iso(3600)),
                    "end": .string(iso(0)),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - update

    @MainActor
    @Test("calendar.events.update updates an existing event in place")
    func updateInPlace() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        let created = try await CalendarEventsCreateTool(writer: provider).call(
            args: .object([
                "title": .string("Original"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
                "calendar_id": .string("nexus-cal"),
            ]),
            context: fixture.context
        )
        let createdDTO = try TasksToolJSON.decode(CalendarEventDTO.self, from: created)

        _ = try await CalendarEventsUpdateTool(writer: provider).call(
            args: .object([
                "event_id": .string(createdDTO.id),
                "title": .string("Renamed"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
                "calendar_id": .string("nexus-cal"),
            ]),
            context: fixture.context
        )
        #expect(provider.updatedIDs == [createdDTO.id])
        let snapshots = try await provider.events(
            inCalendar: "nexus-cal",
            start: Self.now.addingTimeInterval(-1),
            end: Self.now.addingTimeInterval(7200)
        )
        #expect(snapshots.first?.title == "Renamed")
    }

    // MARK: - delete

    @MainActor
    @Test("calendar.events.delete removes the event")
    func deleteRemovesEvent() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        let created = try await CalendarEventsCreateTool(writer: provider).call(
            args: .object([
                "title": .string("Doomed"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
            ]),
            context: fixture.context
        )
        let id = try TasksToolJSON.decode(CalendarEventDTO.self, from: created).id

        let result = try await CalendarEventsDeleteTool(writer: provider).call(
            args: .object(["event_id": .string(id)]),
            context: fixture.context
        )
        #expect(result["deleted"]?.boolValue == true)
        #expect(provider.deletedIDs == [id])
    }

    // MARK: - builder

    @MainActor
    @Test("CalendarAgentTools.tools exposes the full spec §12 set")
    func builderExposesAllTools() {
        let provider = FakeCalendarProvider()
        let names = Set(CalendarAgentTools.tools(provider: provider).map(\.name))
        #expect(
            names == [
                "tasks.estimate_duration",
                "schedule.plan_day",
                "schedule.accept_block",
                "schedule.reject_block",
                "schedule.deadline_risks",
                "calendar.events.list",
                "calendar.events.create",
                "calendar.events.update",
                "calendar.events.delete",
            ]
        )
    }
}
