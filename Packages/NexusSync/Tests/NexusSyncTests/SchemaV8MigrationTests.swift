import Foundation
import NexusCore
import SwiftData
import Testing
@testable import NexusSync

@Suite struct SchemaV8MigrationTests {
    @Test func v8AddsCommentToV7Models() {
        #expect(NexusSchemaV8.models.count == NexusSchemaV7.models.count + 1)
        #expect(NexusSchemaV8.models.contains { $0 == Comment.self })
    }

    @Test func migrationPlanIncludesV8Stage() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV8.self })
    }

    @Test func taskWithRemindersPersistsInV8Container() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(NexusSchemaV8.models, version: NexusSchemaV8.versionIdentifier),
            configurations: config
        )
        let context = ModelContext(container)
        let task = TaskItem(title: "remind me")
        task.reminders = [.relative(offset: -1800, anchor: .due)]
        context.insert(task)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.first?.reminders == [.relative(offset: -1800, anchor: .due)])
    }
}
