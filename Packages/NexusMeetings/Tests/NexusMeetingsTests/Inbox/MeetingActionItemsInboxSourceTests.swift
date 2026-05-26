import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
@Test func meetingActionItemsInboxSourceSurfacesLinkedOpenTasks() async throws {
    let environment = try makeInboxEnvironment(now: Date(timeIntervalSince1970: 1_800_000_000))
    let meeting = MeetingsTestSupport.meeting(title: "Roadmap review")
    try environment.meetingRepository.insert(meeting)
    let task = TaskItem(title: "Send deck", status: .open, tags: ["followup"])
    task.externalSourceID = "\(MeetingActionItemsInboxSource.identifier):fixture"
    try environment.taskRepository.insert(task)
    try environment.linkRepository.findOrCreate(
        from: (.meeting, meeting.id),
        to: (.task, task.id),
        linkKind: .actionItem
    )

    let source = MeetingActionItemsInboxSource(
        meetingRepository: environment.meetingRepository,
        taskRepository: environment.taskRepository,
        linkRepository: environment.linkRepository
    )

    let items = try await source.items()

    #expect(items.count == 1)
    let item = try #require(items.first)
    #expect(item.id == task.id)
    #expect(item.sourceID == MeetingActionItemsInboxSource.identifier)
    #expect(item.title == "Send deck")
    #expect(item.body == "from meeting: Roadmap review")
    #expect(item.tags == ["followup"])
}

@MainActor
@Test func meetingActionItemsInboxSourceExcludesLinkedDoneAndSnoozedTasks() async throws {
    let environment = try makeInboxEnvironment(now: Date(timeIntervalSince1970: 1_800_000_000))
    let meeting = MeetingsTestSupport.meeting(title: "Follow-up review")
    try environment.meetingRepository.insert(meeting)
    let openTask = TaskItem(title: "Send open item", status: .open)
    let doneTask = TaskItem(title: "Already done", status: .done)
    let snoozedTask = TaskItem(title: "Sleeping item", status: .snoozed)
    try environment.taskRepository.insert(openTask)
    try environment.taskRepository.insert(doneTask)
    try environment.taskRepository.insert(snoozedTask)
    for task in [openTask, doneTask, snoozedTask] {
        try environment.linkRepository.findOrCreate(
            from: (.meeting, meeting.id),
            to: (.task, task.id),
            linkKind: .actionItem
        )
    }
    let source = MeetingActionItemsInboxSource(
        meetingRepository: environment.meetingRepository,
        taskRepository: environment.taskRepository,
        linkRepository: environment.linkRepository
    )

    let items = try await source.items()

    #expect(items.map(\.title) == ["Send open item"])
}

@MainActor
@Test func meetingActionItemsInboxSourceArchiveSoftDeletesLinkedTask() async throws {
    let environment = try makeInboxEnvironment(now: Date(timeIntervalSince1970: 1_800_000_000))
    let meeting = MeetingsTestSupport.meeting(title: "Planning")
    try environment.meetingRepository.insert(meeting)
    let task = TaskItem(title: "Archive me", status: .open)
    try environment.taskRepository.insert(task)
    try environment.linkRepository.findOrCreate(
        from: (.meeting, meeting.id),
        to: (.task, task.id),
        linkKind: .actionItem
    )
    let source = MeetingActionItemsInboxSource(
        meetingRepository: environment.meetingRepository,
        taskRepository: environment.taskRepository,
        linkRepository: environment.linkRepository
    )
    let item = try #require(try await source.items().first)

    try await source.archive(item)

    let itemID = item.id
    let descriptor = FetchDescriptor<TaskItem>(
        predicate: #Predicate { task in
            task.id == itemID
        }
    )
    let fetched = try #require(try environment.taskRepository.context.fetch(descriptor).first)
    #expect(fetched.deletedAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(try await source.items().isEmpty)
}

@MainActor
@Test func meetingActionItemsInboxSourceSnoozeUpdatesLinkedTask() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snoozeUntil = Date(timeIntervalSince1970: 1_800_003_600)
    let environment = try makeInboxEnvironment(now: now)
    let meeting = MeetingsTestSupport.meeting(title: "Standup")
    try environment.meetingRepository.insert(meeting)
    let task = TaskItem(title: "Follow up", status: .open)
    try environment.taskRepository.insert(task)
    try environment.linkRepository.findOrCreate(
        from: (.meeting, meeting.id),
        to: (.task, task.id),
        linkKind: .actionItem
    )
    let source = MeetingActionItemsInboxSource(
        meetingRepository: environment.meetingRepository,
        taskRepository: environment.taskRepository,
        linkRepository: environment.linkRepository
    )
    let item = try #require(try await source.items().first)

    try await source.snooze(item, until: snoozeUntil)

    let itemID = item.id
    let descriptor = FetchDescriptor<TaskItem>(
        predicate: #Predicate { task in
            task.id == itemID
        }
    )
    let fetched = try #require(try environment.taskRepository.context.fetch(descriptor).first)
    #expect(fetched.status == .snoozed)
    #expect(fetched.snoozedUntil == snoozeUntil)
    #expect(try await source.items().isEmpty)
}

@MainActor
private func makeInboxEnvironment(now: Date) throws -> InboxTestEnvironment {
    let context = try MeetingsTestSupport.makeContext()
    return InboxTestEnvironment(
        meetingRepository: MeetingRepository(context: context),
        taskRepository: TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { now }
        ),
        linkRepository: LinkRepository(context: context)
    )
}

private struct InboxTestEnvironment {
    let meetingRepository: MeetingRepository
    let taskRepository: TaskItemRepository
    let linkRepository: LinkRepository
}
