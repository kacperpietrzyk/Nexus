import Foundation
import NexusAI
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

/// Deterministic `DateExtracting` stub: resolves a single known hint to a fixed
/// date and returns `nil` for everything else. Keeps these tests independent of
/// the real NL parser (which lives in TasksFeature and is exercised there).
private struct StubDateExtractor: DateExtracting {
    let knownHint: String
    let resolved: Date

    func date(from hint: String, now: Date, locale: Locale) async -> Date? {
        hint.caseInsensitiveCompare(knownHint) == .orderedSame ? resolved : nil
    }
}

@MainActor
private func makeStage(
    context: ModelContext,
    meetingRepository: MeetingRepository,
    taskRepository: TaskItemRepository,
    linkRepository: LinkRepository,
    router: any MeetingProcessingRouting,
    dateExtractor: (any DateExtracting)? = nil
) -> ActionItemsStage {
    ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items",
        dateExtractor: dateExtractor
    )
}

@MainActor
@Test func actionItemsStageResolvesDueHintForMaterializedItem() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepository = MeetingRepository(context: context)
    let taskRepository = TaskItemRepository(
        context: context,
        scheduler: RRuleScheduler(),
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let linkRepository = LinkRepository(context: context)
    let meeting = MeetingsTestSupport.meeting()
    try meetingRepository.insert(meeting)

    let due = Date(timeIntervalSince1970: 1_700_500_000)
    let router = StubActionItemsRouter(
        text: """
            [
              {
                "text": "Send the deck",
                "assigneeHint": "Me",
                "dueHint": "by Friday",
                "confidence": 0.9
              }
            ]
            """)
    let stage = makeStage(
        context: context,
        meetingRepository: meetingRepository,
        taskRepository: taskRepository,
        linkRepository: linkRepository,
        router: router,
        dateExtractor: StubDateExtractor(knownHint: "by Friday", resolved: due)
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    let task = try #require(output.autoCreated.first)
    #expect(task.dueAt == due)
    #expect(output.notMine.isEmpty)
}

@MainActor
@Test func actionItemsStageLeavesDueAtNilWhenHintUnresolved() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepository = MeetingRepository(context: context)
    let taskRepository = TaskItemRepository(
        context: context,
        scheduler: RRuleScheduler(),
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let linkRepository = LinkRepository(context: context)
    let meeting = MeetingsTestSupport.meeting()
    try meetingRepository.insert(meeting)

    let router = StubActionItemsRouter(
        text: """
            [
              {
                "text": "Send the deck",
                "assigneeHint": "Me",
                "dueHint": "whenever-ish",
                "confidence": 0.9
              }
            ]
            """)
    let stage = makeStage(
        context: context,
        meetingRepository: meetingRepository,
        taskRepository: taskRepository,
        linkRepository: linkRepository,
        router: router,
        dateExtractor: StubDateExtractor(
            knownHint: "by Friday",
            resolved: Date(timeIntervalSince1970: 1_700_500_000)
        )
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    let task = try #require(output.autoCreated.first)
    #expect(task.dueAt == nil)
}

@MainActor
@Test func actionItemsStageDoesNotMaterializeOthersActionItem() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepository = MeetingRepository(context: context)
    let taskRepository = TaskItemRepository(
        context: context,
        scheduler: RRuleScheduler(),
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let linkRepository = LinkRepository(context: context)
    let meeting = MeetingsTestSupport.meeting()
    try meetingRepository.insert(meeting)

    let router = StubActionItemsRouter(
        text: """
            [
              {
                "text": "Alice sends the deck",
                "assigneeHint": "Alice",
                "dueHint": "by Friday",
                "confidence": 0.95
              }
            ]
            """)
    let stage = makeStage(
        context: context,
        meetingRepository: meetingRepository,
        taskRepository: taskRepository,
        linkRepository: linkRepository,
        router: router
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    #expect(output.autoCreated.isEmpty)
    #expect(output.notMine.count == 1)
    #expect(output.notMine.first?.assigneeHint == "Alice")
    // No task persisted, no link, no actionItemIDs recorded.
    #expect(try context.fetch(FetchDescriptor<TaskItem>()).filter { $0.deletedAt == nil }.isEmpty)
    #expect(try meetingRepository.find(id: meeting.id)?.actionItemIDs.isEmpty == true)
    #expect(try linkRepository.outgoing(from: (.meeting, meeting.id)).isEmpty)
}

@MainActor
@Test func actionItemsStageMaterializesItemWithNilAssignee() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepository = MeetingRepository(context: context)
    let taskRepository = TaskItemRepository(
        context: context,
        scheduler: RRuleScheduler(),
        now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let linkRepository = LinkRepository(context: context)
    let meeting = MeetingsTestSupport.meeting()
    try meetingRepository.insert(meeting)

    let router = StubActionItemsRouter(
        text: """
            [
              {
                "text": "Send the deck",
                "assigneeHint": null,
                "dueHint": null,
                "confidence": 0.9
              }
            ]
            """)
    let stage = makeStage(
        context: context,
        meetingRepository: meetingRepository,
        taskRepository: taskRepository,
        linkRepository: linkRepository,
        router: router
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    #expect(output.autoCreated.count == 1)
    #expect(output.notMine.isEmpty)
    let task = try #require(output.autoCreated.first)
    #expect(task.dueAt == nil)
    // assigneeHint is never persisted onto the task (single-user, no assignee field).
    #expect(task.assignedAgent == nil)
}

private actor StubActionItemsRouter: MeetingProcessingRouting {
    private let text: String

    init(text: String) {
        self.text = text
    }

    func route(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: text, providerUsed: .appleIntelligence)
    }
}
