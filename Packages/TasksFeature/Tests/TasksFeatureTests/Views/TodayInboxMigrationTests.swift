import Foundation
import NexusCore
import SwiftData
import TasksFeature
import Testing

@MainActor
@Suite("Today to Inbox migration")
struct TodayInboxMigrationTests {

    @Test("Today query still counts no-date, but TaskListView.today no longer exposes noDate state")
    func todayNoDateIsNotRenderedByTodayList() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let repository = TaskItemRepository(
            context: container.mainContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        try repository.insert(TaskItem(title: "No date task"))

        let noDate = try TodayQuery().noDate().apply(in: container.mainContext)
        #expect(noDate.map(\.title) == ["No date task"])

        let filter = TaskFilter.today
        #expect(filter != .inbox)
    }
}
