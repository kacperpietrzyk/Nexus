import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("I-D1 template inertness — TasksFeature surfaces")
struct TemplateInertnessFeatureTests {
    @MainActor
    private struct Harness {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let container: ModelContainer
        let context: ModelContext
        let repository: TaskItemRepository

        init() throws {
            let schema = Schema([TaskItem.self, Project.self, Section.self, Note.self, Link.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            self.container = try ModelContainer(for: schema, configurations: [config])
            self.context = ModelContext(container)
            self.repository = TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
        }
    }

    @MainActor
    @Test("TaskListView .all and .completed statics exclude templates")
    func allAndCompletedExcludeTemplates() throws {
        let harness = try Harness()
        harness.context.insert(TaskItem(title: "live"))
        harness.context.insert(TaskItem(title: "tpl", isTemplate: true))
        try harness.context.save()

        let all = try TaskListView.tasks(status: nil, modelContext: harness.context)
        #expect(all.map(\.title) == ["live"])
        let done = try TaskListView.tasks(status: .done, modelContext: harness.context)
        #expect(done.isEmpty)
    }

    @MainActor
    @Test("TaskListView.inboxTasks excludes snoozed templates")
    func inboxExcludesSnoozedTemplates() throws {
        let harness = try Harness()
        // Bypass the repository on purpose: the repo's own snooze guard (Task 2)
        // makes template-snoozing impossible going forward, but synced rows from
        // an older build could still carry this shape — the read side must hold.
        let template = TaskItem(title: "tpl", isTemplate: true)
        template.statusRaw = TaskStatus.snoozed.rawValue
        template.snoozedUntil = harness.now.addingTimeInterval(3_600)
        harness.context.insert(template)
        let live = TaskItem(title: "live")
        harness.context.insert(live)
        try harness.context.save()

        let inbox = try TaskListView.inboxTasks(now: harness.now, modelContext: harness.context)
        #expect(inbox.map(\.title) == ["live"])
    }

    @MainActor
    @Test("TasksSnoozedSource excludes snoozed templates")
    func snoozedSourceExcludesTemplates() async throws {
        let harness = try Harness()
        let template = TaskItem(title: "tpl", isTemplate: true)
        template.statusRaw = TaskStatus.snoozed.rawValue
        template.snoozedUntil = harness.now.addingTimeInterval(3_600)
        harness.context.insert(template)
        try harness.context.save()

        let source = TasksSnoozedSource(
            repository: harness.repository,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let items = try await source.items()
        #expect(items.isEmpty)
    }

    @MainActor
    @Test("NotificationSnapshotEncoder excludes templates")
    func snapshotEncoderExcludesTemplates() throws {
        let harness = try Harness()
        let template = TaskItem(
            title: "tpl",
            dueAt: harness.now.addingTimeInterval(3_600),
            isTemplate: true
        )
        let live = TaskItem(title: "live", dueAt: harness.now.addingTimeInterval(3_600))
        harness.context.insert(template)
        harness.context.insert(live)
        try harness.context.save()

        let snapshot = NotificationSnapshotEncoder(context: harness.context)
            .encode(now: harness.now, horizon: 24 * 3_600)
        #expect(snapshot.entries.map(\.title) == ["live"])
    }
}
