import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("UpcomingQuery")
struct UpcomingQueryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        return Calendar.gregorianUTC.date(from: comps)!
    }

    @MainActor
    @Test("next seven days excludes today and day eight")
    func nextSeven() throws {
        let context = try makeContext()
        let now = date(2026, 5, 4)
        context.insert(TaskItem(title: "today", dueAt: date(2026, 5, 4)))
        context.insert(TaskItem(title: "tomorrow", dueAt: date(2026, 5, 5)))
        context.insert(TaskItem(title: "day7", dueAt: date(2026, 5, 11)))
        context.insert(TaskItem(title: "day8", dueAt: date(2026, 5, 12)))
        try context.save()

        let titles = try UpcomingQuery(calendar: .gregorianUTC)
            .next(days: 7, from: now)
            .apply(in: context)
            .map(\.title)
            .sorted()
        #expect(titles == ["day7", "tomorrow"])
    }

    @MainActor
    @Test("next seven days excludes tasks owned by archived projects when ids provided")
    func nextSevenExcludesArchivedProjectTasks() throws {
        let context = try makeContext()
        let now = date(2026, 5, 4)
        let archivedProjectID = UUID()
        let activeProjectID = UUID()
        context.insert(
            TaskItem(title: "archived tomorrow", dueAt: date(2026, 5, 5), projectID: archivedProjectID)
        )
        context.insert(
            TaskItem(title: "active tomorrow", dueAt: date(2026, 5, 5), projectID: activeProjectID)
        )
        try context.save()

        let titles = try UpcomingQuery(calendar: .gregorianUTC)
            .next(days: 7, from: now, excludingProjectIDs: [archivedProjectID])
            .apply(in: context)
            .map(\.title)
        #expect(titles == ["active tomorrow"])

        // Without exclusion both rows surface.
        let allTitles = try UpcomingQuery(calendar: .gregorianUTC)
            .next(days: 7, from: now)
            .apply(in: context)
            .map(\.title)
            .sorted()
        #expect(allTitles == ["active tomorrow", "archived tomorrow"])
    }
}
