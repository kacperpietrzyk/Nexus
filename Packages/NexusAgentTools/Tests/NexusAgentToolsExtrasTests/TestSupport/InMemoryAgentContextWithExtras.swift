import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import TasksFeature

@testable import NexusAgentToolsExtras

@MainActor
enum InMemoryAgentContextWithExtras {
    // swiftlint:disable large_tuple
    static func make(
        tasks: [TaskItem] = [],
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) async throws -> (context: AgentContext, container: ModelContainer, repo: TaskItemRepository) {
        let schema = Schema([
            Link.self, DebugItem.self, QuotaLog.self, TaskItem.self, Project.self,
            Section.self, Comment.self, Note.self, ScheduledBlock.self, Label.self,
            Person.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let modelContext = ModelContext(container)
        let repo = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: now
        )

        for task in tasks {
            modelContext.insert(task)
        }
        try modelContext.save()

        let searchIndex = SearchIndex()
        try await searchIndex.rebuild(from: modelContext, types: TaskItem.self)
        let handcodedParser = HandcodedParser()
        let parserRef = AnyNLParserRef { input, locale, now in
            await handcodedParser.parse(input, locale: locale, now: now)
        }
        let heroBriefRef = HeroBriefServiceRef { modelContext, currentTime in
            let rows = (try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
            let open = rows.filter { task in
                task.deletedAt == nil && task.status == .open
            }
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: currentTime)
            let startOfTomorrow =
                calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay
            let overdue = open.filter { task in
                guard let dueAt = task.dueAt else { return false }
                return dueAt < startOfDay
            }.count
            let today = open.filter { task in
                guard let dueAt = task.dueAt else { return false }
                return dueAt >= startOfDay && dueAt < startOfTomorrow
            }.count
            let inbox = open.filter { $0.dueAt == nil }.count
            return "Today: \(today) due, \(overdue) overdue, \(inbox) inbox"
        }

        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: searchIndex,
            now: now,
            nlParser: parserRef,
            heroBriefService: heroBriefRef
        )
        return (agentContext, container, repo)
    }
    // swiftlint:enable large_tuple
}
