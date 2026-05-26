import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@MainActor
@Suite("TaskDetailInspector blocks")
struct TaskDetailInspectorBlocksTests {

    @Test("addBlock appears in awaiting")
    func addBlock_appearsInAwaiting() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()

        let actions = TaskDetailInspectorBlocksActions(task: blocker, linkRepository: repo)
        try actions.addBlock(target: blocked)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)
        #expect(entries.map(\.task.title) == ["blocker"])
        #expect(entries.first?.blockedCount == 1)
    }

    @Test("removeBlock deletes link")
    func removeBlock_deletesLink() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, blocker.id), to: (.task, blocked.id), linkKind: .blocks)

        let actions = TaskDetailInspectorBlocksActions(task: blocker, linkRepository: repo)
        try actions.removeBlock(targetID: blocked.id)

        #expect(try repo.outgoingBlocks(from: (.task, blocker.id)).isEmpty)
    }

    @Test("removeBlock targetID preserves non-task endpoint with same UUID")
    func removeBlock_targetIDPreservesNonTaskEndpointWithSameUUID() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        let noteLink = try repo.create(from: (.task, blocker.id), to: (.note, blocked.id), linkKind: .blocks)

        let actions = TaskDetailInspectorBlocksActions(task: blocker, linkRepository: repo)
        try actions.removeBlock(targetID: blocked.id)

        let outgoing = try repo.outgoingBlocks(from: (.task, blocker.id))
        #expect(outgoing.map(\.id) == [noteLink.id])
        #expect(outgoing.first?.toKind == .note)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
