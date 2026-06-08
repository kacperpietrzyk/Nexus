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
}
