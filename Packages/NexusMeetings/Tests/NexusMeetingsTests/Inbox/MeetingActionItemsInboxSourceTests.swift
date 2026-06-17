import Foundation
import InboxShell
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
@Test func meetingActionItemsInboxSourceBatchedMatchesPerMeetingReference() async throws {
    // Characterization: the batched `items()` must be byte-identical to the
    // legacy per-meeting `outgoing(from:)` + all-open-tasks path. Discriminators:
    // - multiple meetings, distinct createdAt per task (total-order sort, no ties)
    // - a non-action link (.relates) that must NOT surface
    // - a closed task + a soft-deleted task linked as action items (excluded)
    // - one task linked as an action item from TWO meetings (must yield two items)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let environment = try makeInboxEnvironment(now: now)

    let alpha = MeetingsTestSupport.meeting(title: "Alpha sync")
    let beta = MeetingsTestSupport.meeting(title: "Beta planning")
    try environment.meetingRepository.insert(alpha)
    try environment.meetingRepository.insert(beta)

    func task(_ title: String, createdOffset: TimeInterval, status: TaskStatus = .open, tags: [String] = []) -> TaskItem {
        let item = TaskItem(title: title, status: status, tags: tags)
        item.createdAt = now.addingTimeInterval(createdOffset)
        return item
    }

    let openA = task("Ship deck", createdOffset: 300, tags: ["followup"])
    let openB = task("Draft notes", createdOffset: 200)
    let shared = task("Cross-meeting item", createdOffset: 100)
    let closed = task("Already closed", createdOffset: 50, status: .done)
    let deleted = task("Soft deleted", createdOffset: 40)
    let nonAction = task("Just related", createdOffset: 30)
    for item in [openA, openB, shared, closed, deleted, nonAction] {
        try environment.taskRepository.insert(item)
    }
    deleted.deletedAt = now
    try environment.taskRepository.context.save()

    // Action-item links: alpha -> openA, shared, closed, deleted; beta -> openB, shared.
    for (meeting, task) in [
        (alpha, openA), (alpha, shared), (alpha, closed), (alpha, deleted),
        (beta, openB), (beta, shared),
    ] {
        try environment.linkRepository.findOrCreate(
            from: (.meeting, meeting.id),
            to: (.task, task.id),
            linkKind: .actionItem
        )
    }
    // Non-action link must be ignored.
    try environment.linkRepository.findOrCreate(
        from: (.meeting, alpha.id),
        to: (.task, nonAction.id),
        linkKind: .mentions
    )

    let expected = try referenceItems(environment: environment, now: now)

    let source = MeetingActionItemsInboxSource(
        meetingRepository: environment.meetingRepository,
        taskRepository: environment.taskRepository,
        linkRepository: environment.linkRepository
    )
    let items = try await source.items()

    #expect(items.count == expected.count)
    #expect(items.map(\.id) == expected.map(\.id))
    #expect(items.map(\.title) == expected.map(\.title))
    #expect(items.map(\.body) == expected.map(\.body))
    #expect(items.map(\.tags) == expected.map(\.tags))
    #expect(items.map(\.due) == expected.map(\.due))
    #expect(items.map(\.createdAt) == expected.map(\.createdAt))
    #expect(items.map(\.sourceID) == expected.map(\.sourceID))

    // The cross-meeting task surfaces once per meeting (no cross-meeting dedup),
    // with distinct bodies; closed/deleted/non-action linked tasks are absent.
    let sharedItems = items.filter { $0.id == shared.id }
    #expect(sharedItems.count == 2)
    #expect(Set(sharedItems.map(\.body)) == ["from meeting: Alpha sync", "from meeting: Beta planning"])
    #expect(items.contains { $0.id == closed.id } == false)
    #expect(items.contains { $0.id == deleted.id } == false)
    #expect(items.contains { $0.id == nonAction.id } == false)
}

/// Reference implementation: the legacy per-meeting `outgoing(from:)` + fetch-all-open
/// path the batched `items()` replaced. The two MUST produce byte-identical output.
@MainActor
private func referenceItems(environment: InboxTestEnvironment, now: Date) throws -> [InboxItem] {
    let sourceID = MeetingActionItemsInboxSource.identifier
    let meetings = try environment.meetingRepository.allChronological().filter { $0.deletedAt == nil }
    let taskIDsByMeetingID = try meetings.reduce(into: [UUID: Set<UUID>]()) { result, meeting in
        let links = try environment.linkRepository.outgoing(from: (.meeting, meeting.id))
        let taskIDs = links.compactMap { link -> UUID? in
            guard link.linkKind == .actionItem, link.toKind == .task else { return nil }
            return link.toID
        }
        if taskIDs.isEmpty == false {
            result[meeting.id] = Set(taskIDs)
        }
    }
    let allTaskIDs = Set(taskIDsByMeetingID.values.flatMap { $0 })
    guard allTaskIDs.isEmpty == false else { return [] }

    let openStatus = TaskStatus.open.rawValue
    let taskDescriptor = FetchDescriptor<TaskItem>(
        predicate: #Predicate { task in
            task.deletedAt == nil && task.statusRaw == openStatus
        }
    )
    let tasksByID = Dictionary(
        try environment.taskRepository.context.fetch(taskDescriptor)
            .filter { allTaskIDs.contains($0.id) }
            .map { ($0.id, $0) },
        uniquingKeysWith: { current, _ in current }
    )

    return meetings.flatMap { meeting -> [InboxItem] in
        guard let taskIDs = taskIDsByMeetingID[meeting.id] else { return [] }
        return taskIDs.compactMap { taskID in
            guard let task = tasksByID[taskID] else { return nil }
            return InboxItem(
                id: task.id,
                sourceID: sourceID,
                title: task.title,
                body: "from meeting: \(meeting.title)",
                due: task.dueAt,
                tags: task.tags,
                createdAt: task.createdAt
            )
        }
    }
    .sorted {
        if $0.createdAt != $1.createdAt {
            return $0.createdAt > $1.createdAt
        }
        return $0.title < $1.title
    }
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
