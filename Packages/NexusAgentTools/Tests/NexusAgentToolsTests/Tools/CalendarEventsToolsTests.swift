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
    @Test("calendar.events.list echoes all-day and calendar id from the source event (A4)")
    func listCarriesAllDayAndCalendarID() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let event = CalendarEvent(
            id: "e1",
            title: "Holiday",
            start: Self.now,
            end: Self.now.addingTimeInterval(86_400),
            isAllDay: true,
            calendarID: "work-cal"
        )
        let provider = FakeCalendarProvider(stubEvents: [event])

        let result = try await CalendarEventsListTool(provider: provider).call(
            args: .object(["start": .string(iso(-3600)), "end": .string(iso(90_000))]),
            context: fixture.context
        )
        let dto = try #require(try TasksToolJSON.decode([CalendarEventDTO].self, from: result).first)
        #expect(dto.isAllDay == true)
        #expect(dto.calendarID == "work-cal")
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

    @MainActor
    @Test("calendar.events.create carries recurrence and alarms into the draft")
    func createCarriesRecurrenceAndAlarms() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()

        _ = try await CalendarEventsCreateTool(writer: provider).call(
            args: .object([
                "title": .string("Planning"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
                "recurrence_rule": .string("FREQ=WEEKLY;BYDAY=MO"),
                "alarm_offsets": .array([.int(-900), .double(-60)]),
            ]),
            context: fixture.context
        )

        let draft = try #require(provider.createdDrafts.first)
        #expect(draft.recurrence?.frequency == .weekly)
        #expect(draft.recurrence?.byWeekday == [.monday])
        #expect(draft.alarmOffsets == [-900, -60])
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

    @MainActor
    @Test("calendar.events.update carries recurrence and alarms into the draft")
    func updateCarriesRecurrenceAndAlarms() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        let created = try await CalendarEventsCreateTool(writer: provider).call(
            args: .object([
                "title": .string("Original"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
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
                "recurrence_rule": .string("FREQ=DAILY;COUNT=3"),
                "alarm_offsets": .array([.int(-300)]),
            ]),
            context: fixture.context
        )

        let draft = try #require(provider.updatedDrafts.first)
        #expect(draft.recurrence?.frequency == .daily)
        #expect(draft.recurrence?.count == 3)
        #expect(draft.alarmOffsets == [-300])
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

    // MARK: - calendar target: none / default (#7)

    private func isolatedStore(_ prefs: CalendarPreferences = .default) -> UserDefaultsCalendarPreferencesStore {
        let store = UserDefaultsCalendarPreferencesStore(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        store.save(prefs)
        return store
    }

    @MainActor
    @Test("calendar.events.create with calendar_id \"none\" skips the system-calendar write (#7)")
    func createNoneSkipsWrite() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()

        let result = try await CalendarEventsCreateTool(
            writer: provider, preferencesStore: isolatedStore()
        ).call(
            args: .object([
                "title": .string("Private note event"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
                "calendar_id": .string("none"),
            ]),
            context: fixture.context
        )

        #expect(result["skipped"]?.boolValue == true)
        // No EKEvent persisted (the dedup probe never ran, the draft carried nil).
        #expect(provider.store.isEmpty)
        #expect(provider.ensureNexusCount == 0)
        // The draft was still recorded with a nil calendar.
        #expect(provider.createdDrafts.first?.calendarID == nil)
    }

    @MainActor
    @Test("calendar.events.create omitted calendar honors the configured write target (#7)")
    func createOmittedHonorsDefault() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        let store = isolatedStore(CalendarPreferences(writeCalendarID: "my-default-cal"))

        let result = try await CalendarEventsCreateTool(
            writer: provider, preferencesStore: store
        ).call(
            args: .object([
                "title": .string("Focus block"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
            ]),
            context: fixture.context
        )

        let dto = try TasksToolJSON.decode(CalendarEventDTO.self, from: result)
        #expect(dto.calendarID == "my-default-cal")
        // The default was used directly — the "Nexus" calendar was never forced.
        #expect(provider.ensureNexusCount == 0)
    }

    @MainActor
    @Test("calendar.events.create omitted with no configured target falls back to Nexus (#7)")
    func createOmittedFallsBackToNexus() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()

        let result = try await CalendarEventsCreateTool(
            writer: provider, preferencesStore: isolatedStore()
        ).call(
            args: .object([
                "title": .string("Focus block"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
            ]),
            context: fixture.context
        )

        let dto = try TasksToolJSON.decode(CalendarEventDTO.self, from: result)
        #expect(dto.calendarID == "nexus-cal")
        #expect(provider.ensureNexusCount == 1)
    }

    @MainActor
    @Test("calendar.events.update with omitted calendar leaves the event's calendar unchanged (#7)")
    func updateOmittedKeepsCalendar() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.clock)
        let provider = FakeCalendarProvider()
        let created = try await CalendarEventsCreateTool(
            writer: provider, preferencesStore: isolatedStore()
        ).call(
            args: .object([
                "title": .string("Original"),
                "start": .string(iso(0)),
                "end": .string(iso(3600)),
                "calendar_id": .string("team-cal"),
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
            ]),
            context: fixture.context
        )

        // The update draft carried nil (no reassignment); the stored event keeps
        // its original calendar.
        #expect(provider.updatedDrafts.first?.calendarID == nil)
        let snapshot = try await provider.eventSnapshot(id: createdDTO.id)
        #expect(snapshot?.calendarID == "team-cal")
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
