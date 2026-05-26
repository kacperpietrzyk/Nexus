#if canImport(AppIntents)
import Foundation
import NexusCore
import SwiftData
import TasksFeature
import Testing

@MainActor
@Suite("TaskIntentRuntime", .serialized)
struct TaskIntentRuntimeTests {

    @Test("addTask parses and inserts a task")
    func addTask() async throws {
        let harness = try Harness()
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        let entity = try await TaskIntentRuntime.shared.addTask(input: "call mom #home")

        #expect(entity.title == "call mom")
        #expect(entity.tags == ["home"])
        let stored = try harness.repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.first?.endAt == StubParser.endAt)
        #expect(stored.first?.deadlineAt == StubParser.deadlineAt)
    }

    @Test("query resolves entities by title")
    func queryByTitle() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Renew passport")
        try harness.repository.insert(task)
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        let matches = try await TaskEntityQuery().entities(matching: "passport")

        #expect(matches.map(\.id) == [task.id.uuidString])
    }

    @Test("mark done and snooze mutate the selected entity")
    func markDoneAndSnooze() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Pay invoice")
        try harness.repository.insert(task)
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)
        let entity = TaskAppEntity(task: task)

        try await TaskIntentRuntime.shared.markDone(entity)
        try await TaskIntentRuntime.shared.snooze(entity, until: harness.now.addingTimeInterval(3600))

        #expect(task.status == .snoozed)
        #expect(task.snoozedUntil == harness.now.addingTimeInterval(3600))
    }

    @Test("mark done cascades open subtasks")
    func markDoneCascadesOpenSubtasks() async throws {
        let harness = try Harness()
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        try harness.repository.insert(parent)
        try harness.repository.insert(child)
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        try await TaskIntentRuntime.shared.markDone(TaskAppEntity(task: parent))

        #expect(parent.status == .done)
        #expect(child.status == .done)
    }

    @Test("addTask throws emptyInput for blank string")
    func addTaskEmptyInput() async throws {
        let harness = try Harness()
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        await #expect(throws: TaskIntentRuntimeError.emptyInput) {
            _ = try await TaskIntentRuntime.shared.addTask(input: "   ")
        }
    }

    @Test("markDone throws taskNotFound for unknown id")
    func markDoneNotFound() async throws {
        let harness = try Harness()
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)
        let phantom = TaskAppEntity(id: UUID().uuidString, title: "ghost", tags: [])

        await #expect(throws: TaskIntentRuntimeError.taskNotFound) {
            try await TaskIntentRuntime.shared.markDone(phantom)
        }
    }

    @Test("entities(for:) returns only requested ids and ignores absent ones")
    func entities_for_filtersToRequestedIDs() async throws {
        let harness = try Harness()
        let target = TaskItem(title: "target")
        let other = TaskItem(title: "other")
        try harness.repository.insert(target)
        try harness.repository.insert(other)
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        let phantom = UUID().uuidString
        let entities = try TaskIntentRuntime.shared.entities(for: [target.id.uuidString, phantom])
        #expect(entities.map(\.id) == [target.id.uuidString])
    }

    @Test("entities(matching:) caps results at 10")
    func entities_matching_capsAtTen() async throws {
        let harness = try Harness()
        for i in 0..<15 {
            try harness.repository.insert(TaskItem(title: "task \(i)"))
        }
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        let matches = try TaskIntentRuntime.shared.entities(matching: "task")
        #expect(matches.count == 10)
    }

    @Test("entities(matching:) treats whitespace-only query as empty and returns open tasks")
    func entities_matching_emptyQuery_returnsAllOpenWithCap() async throws {
        let harness = try Harness()
        try harness.repository.insert(TaskItem(title: "alpha"))
        try harness.repository.insert(TaskItem(title: "beta"))
        TaskIntentRuntime.configure(parser: StubParser(), repository: harness.repository)

        let matches = try TaskIntentRuntime.shared.entities(matching: "   ")
        #expect(matches.count == 2)
    }
}

private struct StubParser: NLParser {
    static let endAt = Date(timeIntervalSince1970: 1_778_162_400)
    static let deadlineAt = Date(timeIntervalSince1970: 1_778_508_000)

    func parse(_ input: String, locale: Locale, now: Date, calendar: Calendar) async -> ParseResult {
        ParseResult(
            title: input.replacingOccurrences(of: " #home", with: ""),
            dueAt: nil,
            startAt: nil,
            endAt: Self.endAt,
            deadlineAt: Self.deadlineAt,
            priority: nil,
            tags: input.contains("#home") ? ["home"] : [],
            recurrence: nil,
            confidence: 1.0
        )
    }
}

@MainActor
private struct Harness {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let repository: TaskItemRepository

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: TaskItem.self, configurations: config)
        self.repository = TaskItemRepository(
            context: container.mainContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}
#endif
