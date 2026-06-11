import Foundation
import NexusCore
import SwiftData
import Testing

@testable import CalendarFeature

@Suite("CalendarViewModel auto-replan")
@MainActor
struct CalendarViewModelConflictTests {
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

    // 2026-06-08 09:00 UTC — inside the default 09:00–18:00 working window.
    private let now = Date(timeIntervalSince1970: 1_780_650_000)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        now.addingTimeInterval(TimeInterval((hour - 9) * 3600 + minute * 60))
    }

    private func makeViewModel(
        context: ModelContext,
        reader: MockCalendarEventProvider,
        writer: MockCalendarWriter,
        changes: MockCalendarChangeObserver? = nil
    ) -> CalendarViewModel {
        let store = UserDefaultsCalendarPreferencesStore(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )
        let instant = now
        return CalendarViewModel(
            context: context,
            reader: reader,
            writer: writer,
            listing: writer,
            changes: changes,
            changeDebounce: .zero,
            preferencesStore: store,
            calendar: calendar,
            now: { instant }
        )
    }

    private func insertOpenTask(_ context: ModelContext, title: String) throws -> TaskItem {
        let task = TaskItem(title: title, dueAt: now.addingTimeInterval(3600))
        task.estimatedDurationSeconds = 1800
        task.durationSourceRaw = DurationSource.explicit.rawValue
        context.insert(task)
        try context.save()
        return task
    }

    @Test("handleExternalChange regenerates a conflicted proposal around the new event")
    func regeneratesProposal() async throws {
        let context = try makeContext()
        let task = try insertOpenTask(context, title: "write")
        let reader = MockCalendarEventProvider()
        let viewModel = makeViewModel(context: context, reader: reader, writer: MockCalendarWriter())
        await viewModel.load()
        await viewModel.planDay()
        #expect(viewModel.blocks.contains { $0.status == .proposed && $0.start == at(9) })

        reader.setEvents([CalendarEvent(id: "ext-1", title: "standup", start: at(9), end: at(10))])
        await viewModel.handleExternalChange()

        let proposals = viewModel.blocks.filter { $0.status == .proposed }
        #expect(proposals.count == 1)
        #expect(proposals.first?.taskID == task.id)
        #expect(proposals.first?.start == at(10))
        #expect(viewModel.conflictedBlockIDs.isEmpty)
    }

    @Test("an event over an accepted block flags it without moving it")
    func flagsAcceptedBlock() async throws {
        let context = try makeContext()
        let task = try insertOpenTask(context, title: "deep work")
        let reader = MockCalendarEventProvider()
        let writer = MockCalendarWriter()
        let calendarID = try await writer.ensureNexusCalendar()
        let mirrorID = try await writer.createEvent(
            EventDraft(calendarID: calendarID, title: "deep work", start: at(13), end: at(14))
        )
        let repo = ScheduledBlockRepository(context: context)
        let accepted = try repo.create(
            taskID: task.id,
            start: at(13),
            end: at(14),
            title: "deep work",
            status: .accepted,
            externalEventID: mirrorID
        )
        reader.setEvents([
            CalendarEvent(id: mirrorID, title: "deep work", start: at(13), end: at(14)),
            CalendarEvent(id: "ext-2", title: "incoming", start: at(13, 30), end: at(14, 30)),
        ])
        let viewModel = makeViewModel(context: context, reader: reader, writer: writer)
        await viewModel.load()

        await viewModel.handleExternalChange()

        #expect(viewModel.conflictedBlockIDs == [accepted.id])
        #expect(accepted.start == at(13))
        #expect(accepted.end == at(14))
    }

    @Test("replanConflicted tears down conflicted blocks and re-proposes their tasks")
    func replanConflictedReproposes() async throws {
        let context = try makeContext()
        let task = try insertOpenTask(context, title: "deep work")
        let reader = MockCalendarEventProvider()
        let writer = MockCalendarWriter()
        let calendarID = try await writer.ensureNexusCalendar()
        let mirrorID = try await writer.createEvent(
            EventDraft(calendarID: calendarID, title: "deep work", start: at(13), end: at(14))
        )
        let repo = ScheduledBlockRepository(context: context)
        let accepted = try repo.create(
            taskID: task.id,
            start: at(13),
            end: at(14),
            title: "deep work",
            status: .accepted,
            externalEventID: mirrorID
        )
        reader.setEvents([
            CalendarEvent(id: mirrorID, title: "deep work", start: at(13), end: at(14)),
            CalendarEvent(id: "ext-2", title: "incoming", start: at(13, 30), end: at(14, 30)),
        ])
        let viewModel = makeViewModel(context: context, reader: reader, writer: writer)
        await viewModel.load()
        await viewModel.handleExternalChange()
        #expect(viewModel.conflictedBlockIDs == [accepted.id])

        await viewModel.replanConflicted()

        #expect(viewModel.conflictedBlockIDs.isEmpty)
        #expect(!viewModel.blocks.contains { $0.id == accepted.id })
        // The mirror event was torn down (reject-path semantics).
        let snapshot = try await writer.eventSnapshot(id: mirrorID)
        #expect(snapshot == nil)
        // The task came back as a fresh proposal that avoids the incoming event.
        let proposals = viewModel.blocks.filter { $0.status == .proposed }
        #expect(proposals.contains { $0.taskID == task.id })
        #expect(proposals.allSatisfy { $0.end <= at(13, 30) || $0.start >= at(14, 30) })
    }

    @Test("a store-change notification drives the pipeline end-to-end")
    func observerWiring() async throws {
        let context = try makeContext()
        _ = try insertOpenTask(context, title: "write")
        let reader = MockCalendarEventProvider()
        let changes = MockCalendarChangeObserver()
        let viewModel = makeViewModel(
            context: context,
            reader: reader,
            writer: MockCalendarWriter(),
            changes: changes
        )
        await viewModel.load()
        await viewModel.planDay()
        reader.setEvents([CalendarEvent(id: "ext-1", title: "standup", start: at(9), end: at(10))])

        changes.fireChange()

        // Debounce is .zero; poll briefly for the MainActor hop to land.
        for _ in 0..<100 {
            if viewModel.blocks.contains(where: { $0.status == .proposed && $0.start == at(10) }) { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        #expect(viewModel.blocks.contains { $0.status == .proposed && $0.start == at(10) })
    }

    @Test("conflict banner copy pluralizes")
    func conflictNoticeCopy() {
        #expect(CalendarViewModel.conflictNotice(count: 1) == "1 scheduled block conflicts with a calendar event.")
        #expect(CalendarViewModel.conflictNotice(count: 3) == "3 scheduled blocks conflict with calendar events.")
    }
}
