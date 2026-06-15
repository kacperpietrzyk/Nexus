import Foundation
import NexusCore
import SwiftData
import Testing

@testable import CalendarFeature

@Suite("CalendarViewModel")
@MainActor
struct CalendarViewModelTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ScheduledBlock.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // 2026-06-08 09:00 UTC — inside the default working window.
    private let now = Date(timeIntervalSince1970: 1_780_650_000)

    private func makeViewModel(
        context: ModelContext,
        reader: MockCalendarEventProvider = MockCalendarEventProvider(),
        writer: MockCalendarWriter? = MockCalendarWriter(),
        now: Date? = nil
    ) -> CalendarViewModel {
        let store = UserDefaultsCalendarPreferencesStore(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        let instant = now ?? self.now
        return CalendarViewModel(
            context: context,
            reader: reader,
            writer: writer,
            listing: writer,
            preferencesStore: store,
            calendar: calendar,
            now: { instant }
        )
    }

    @Test("planDay persists proposals readable as blocks")
    func planDayProducesBlocks() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "ship it", dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        await viewModel.load()
        await viewModel.planDay()

        #expect(viewModel.blocks.contains { $0.status == .proposed && $0.taskID == task.id })
        #expect(viewModel.planNotice == nil)  // daytime plan → no after-hours notice
    }

    @Test("planDay past working hours surfaces a notice, not a silent empty plan (S8)")
    func planDayAfterHoursNotice() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "late", dueAt: now.addingTimeInterval(13 * 3600 + 1800))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        // 22:00 UTC — past the default 18:00 workday end → today's window collapses.
        let night = now.addingTimeInterval(13 * 3600)
        let viewModel = makeViewModel(context: context, now: night)
        await viewModel.load()
        await viewModel.planDay()

        #expect(viewModel.blocks.isEmpty)
        #expect(viewModel.planNotice != nil)
    }

    @Test("accept flips a proposed block to accepted with a mirror event id")
    func acceptMaterializes() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "do", dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        await viewModel.load()
        await viewModel.planDay()
        let proposed = try #require(viewModel.blocks.first { $0.status == .proposed })

        await viewModel.accept(blockID: proposed.id)

        let reloaded = try #require(viewModel.blocks.first { $0.id == proposed.id })
        #expect(reloaded.status == .accepted)
        #expect(reloaded.externalEventID != nil)
    }

    @Test("reject soft-deletes the block (removed from the visible set)")
    func rejectRemoves() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "drop", dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        await viewModel.load()
        await viewModel.planDay()
        let proposed = try #require(viewModel.blocks.first { $0.status == .proposed })

        viewModel.reject(blockID: proposed.id)
        #expect(!viewModel.blocks.contains { $0.id == proposed.id })
    }

    @Test("No writer: accept surfaces an error and leaves the block proposed")
    func acceptWithoutWriter() async throws {
        let context = try makeContext()
        let block = ScheduledBlock(
            taskID: UUID(),
            start: now,
            end: now.addingTimeInterval(1800),
            status: .proposed
        )
        context.insert(block)
        try context.save()

        let viewModel = makeViewModel(context: context, writer: nil)
        await viewModel.load()
        await viewModel.accept(blockID: block.id)

        #expect(viewModel.lastError != nil)
        let reloaded = try #require(viewModel.blocks.first { $0.id == block.id })
        #expect(reloaded.status == .proposed)
    }

    @Test("Scope window spans the right number of days")
    func scopeWindows() async throws {
        let context = try makeContext()
        let viewModel = makeViewModel(context: context)
        viewModel.anchor = now

        viewModel.scope = .day
        #expect(viewModel.visibleDays.count == 1)
        viewModel.scope = .week
        #expect(viewModel.visibleDays.count == 7)
        viewModel.scope = .month
        #expect(viewModel.visibleDays.count == 42)
    }

    // MARK: - Calendar visibility filter (#6)

    private func stubEvent(id: String, calendarID: String?, at instant: Date) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            start: instant.addingTimeInterval(3_600),
            end: instant.addingTimeInterval(7_200),
            calendarID: calendarID
        )
    }

    @Test("load hides events from calendars outside the read-set (#6)")
    func loadFiltersDisabledCalendars() async throws {
        let context = try makeContext()
        let reader = MockCalendarEventProvider(events: [
            stubEvent(id: "work", calendarID: "work-cal", at: now),
            stubEvent(id: "home", calendarID: "home-cal", at: now),
        ])
        let store = UserDefaultsCalendarPreferencesStore(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        store.save(CalendarPreferences(readCalendarIDs: ["work-cal"]))
        let viewModel = CalendarViewModel(
            context: context,
            reader: reader,
            preferencesStore: store,
            calendar: calendar,
            now: { self.now }
        )

        await viewModel.load()

        #expect(viewModel.events.map(\.id) == ["work"])
    }

    @Test("load with an empty read-set shows every calendar (#6)")
    func loadEmptyReadSetShowsAll() async throws {
        let context = try makeContext()
        let reader = MockCalendarEventProvider(events: [
            stubEvent(id: "work", calendarID: "work-cal", at: now),
            stubEvent(id: "home", calendarID: "home-cal", at: now),
        ])
        let store = UserDefaultsCalendarPreferencesStore(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        store.save(CalendarPreferences(readCalendarIDs: []))
        let viewModel = CalendarViewModel(
            context: context,
            reader: reader,
            preferencesStore: store,
            calendar: calendar,
            now: { self.now }
        )

        await viewModel.load()

        #expect(Set(viewModel.events.map(\.id)) == ["work", "home"])
    }

    // MARK: - Attendee display (#4a)

    @Test("attendeeDisplay formats name+email and keeps name-only attendees (#4a)")
    func attendeeDisplayFormats() {
        let both = CalendarEvent.Attendee(name: "Ada Lovelace", email: "ada@example.com")
        let nameOnly = CalendarEvent.Attendee(name: "Grace Hopper", email: nil)
        let emailOnly = CalendarEvent.Attendee(name: nil, email: "alan@example.com")
        let empty = CalendarEvent.Attendee(name: nil, email: nil)

        #expect(CalendarViewModel.attendeeDisplay(both) == "Ada Lovelace (ada@example.com)")
        #expect(CalendarViewModel.attendeeDisplay(nameOnly) == "Grace Hopper")
        #expect(CalendarViewModel.attendeeDisplay(emailOnly) == "alan@example.com")
        #expect(CalendarViewModel.attendeeDisplay(empty) == nil)
    }

    @Test("week-scope load projects future recurring occurrences WITHOUT persisting any block (M2)")
    func weekLoadProjectsSeriesPreviews() async throws {
        let context = try makeContext()
        let task = TaskItem(
            title: "standup",
            dueAt: now.addingTimeInterval(3600),
            recurrenceRule: "FREQ=DAILY"
        )
        task.estimatedDurationSeconds = 3600
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        viewModel.scope = .week
        await viewModel.load()

        #expect(!viewModel.seriesPreviews.isEmpty)
        #expect(viewModel.seriesPreviews.allSatisfy { $0.taskID == task.id })
        let tomorrowStart = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        #expect(viewModel.seriesPreviews.allSatisfy { $0.start >= tomorrowStart })
        // THE M2 invariant: previews are runtime-only — the store stays empty.
        let persisted = try context.fetch(FetchDescriptor<ScheduledBlock>())
        #expect(persisted.isEmpty)
    }

    @Test("day and month scopes never carry series previews")
    func nonWeekScopesStayEmpty() async throws {
        let context = try makeContext()
        let task = TaskItem(
            title: "standup",
            dueAt: now.addingTimeInterval(3600),
            recurrenceRule: "FREQ=DAILY"
        )
        task.estimatedDurationSeconds = 3600
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        viewModel.scope = .day
        await viewModel.load()
        #expect(viewModel.seriesPreviews.isEmpty)

        viewModel.scope = .month
        await viewModel.load()
        #expect(viewModel.seriesPreviews.isEmpty)
    }

    @Test("manually scheduling a future day suppresses that day's preview (dedup through the live seam)")
    func manualBlockSuppressesPreviewDay() async throws {
        let context = try makeContext()
        let task = TaskItem(
            title: "standup",
            dueAt: now.addingTimeInterval(3600),
            recurrenceRule: "FREQ=DAILY"
        )
        task.estimatedDurationSeconds = 3600
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        viewModel.scope = .week
        await viewModel.load()
        let tomorrowStart = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        #expect(viewModel.seriesPreviews.contains { calendar.isDate($0.start, inSameDayAs: tomorrowStart) })

        await viewModel.addManualBlock(
            taskID: task.id,
            title: "standup",
            start: tomorrowStart.addingTimeInterval(10 * 3600),
            end: tomorrowStart.addingTimeInterval(11 * 3600)
        )

        #expect(!viewModel.seriesPreviews.contains { calendar.isDate($0.start, inSameDayAs: tomorrowStart) })
    }

    @Test("planDay coexists with previews: today gets real proposals, previews stay future and unpersisted")
    func planDayDoesNotConsumePreviews() async throws {
        let context = try makeContext()
        let task = TaskItem(
            title: "standup",
            dueAt: now.addingTimeInterval(3600),
            recurrenceRule: "FREQ=DAILY"
        )
        task.estimatedDurationSeconds = 3600
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()

        let viewModel = makeViewModel(context: context)
        viewModel.scope = .week
        await viewModel.load()
        await viewModel.planDay()

        let todayEnd = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        // Real proposal for the current instance lives today…
        #expect(viewModel.blocks.contains { $0.taskID == task.id && $0.start < todayEnd })
        // …ghost previews remain, all strictly in the future.
        #expect(!viewModel.seriesPreviews.isEmpty)
        #expect(viewModel.seriesPreviews.allSatisfy { $0.start >= todayEnd })
        // And every persisted block is today's (nothing future was written).
        let persisted = try context.fetch(FetchDescriptor<ScheduledBlock>())
        #expect(persisted.filter { $0.deletedAt == nil }.allSatisfy { $0.start < todayEnd })
    }
}
