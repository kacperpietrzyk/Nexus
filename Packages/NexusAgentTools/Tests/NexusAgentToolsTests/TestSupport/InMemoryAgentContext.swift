import Foundation
import NexusCore
import SwiftData

@testable import NexusAgentTools

@MainActor
enum InMemoryAgentContext {
    // swiftlint:disable large_tuple
    static func make(
        tasks: [TaskItem] = [],
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) },
        notifications: any NotificationScheduling = NoopNotificationScheduler()
    ) async throws -> (context: AgentContext, container: ModelContainer, repo: TaskItemRepository) {
        let schema = Schema([
            Link.self, DebugItem.self, QuotaLog.self, TaskItem.self, Project.self,
            Section.self, Comment.self, Note.self, ScheduledBlock.self, Label.self,
            Person.self, Cycle.self, ActivityEntry.self, SavedFilter.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)
        let repo = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: now,
            notifications: notifications,
            // Real-clock recorder (matches production wiring); a fixed `now`
            // would tie every `createdAt` and make newest-first ordering
            // nondeterministic in multi-event tests.
            activity: ActivityRecorder(context: modelContext)
        )

        for task in tasks {
            modelContext.insert(task)
        }
        try modelContext.save()

        let searchIndex = SearchIndex()
        try await searchIndex.rebuild(from: modelContext, types: TaskItem.self)

        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: searchIndex,
            now: now
        )
        return (agentContext, container, repo)
    }
    // swiftlint:enable large_tuple
}
