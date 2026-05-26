import Foundation
import NexusAI
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
// swiftlint:disable:next function_body_length
@Test func actionItemsStageCreatesTaskItemsAndLinks() async throws {
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
                "text": "Send the deck by Friday",
                "assigneeHint": "Me",
                "dueHint": "Friday",
                "confidence": 0.9
              },
              {
                "text": "Maybe later something",
                "assigneeHint": null,
                "dueHint": null,
                "confidence": 0.2
              }
            ]
            """)
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let output = try await stage.run(
        meeting: meeting,
        transcript: "[00:00:00] Me\nPlease send the deck by Friday.",
        summary: "Deck follow-up is needed."
    )

    #expect(output.autoCreated.count == 1)
    #expect(output.lowConfidence.count == 1)
    let request = try #require(await router.capturedRequest)
    #expect(request.prompt.contains("Please send the deck by Friday."))
    #expect(request.prompt.contains("Deck follow-up is needed."))
    #expect(request.capability == .generate)
    #expect(request.connectivity == .offlineOnly)
    #expect(request.cost == .free)
    #expect(request.providerPreference == .auto)

    let task = try #require(output.autoCreated.first)
    #expect(task.title.contains("Send the deck"))
    #expect(task.status == .open)
    let externalSourceID = try #require(task.externalSourceID)
    #expect(externalSourceID.hasPrefix("meetings.action-items:\(meeting.id.uuidString):"))
    #expect(externalSourceID != "meetings.action-items:\(meeting.id.uuidString):0")

    let updated = try #require(try meetingRepository.find(id: meeting.id))
    #expect(updated.actionItemIDs == [task.id])

    let links = try linkRepository.outgoing(from: (.meeting, meeting.id))
    let actionLink = try #require(
        links.first { link in
            link.linkKind == .actionItem && link.toKind == .task && link.toID == task.id
        })
    #expect(actionLink.fromKind == .meeting)
}

@MainActor
@Test func actionItemsStageToleratesFencedJSONWithSurroundingProse() async throws {
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
            Here are the items:
            ```json
            [
              {
                "text": "Send the deck",
                "assigneeHint": "Me",
                "dueHint": null,
                "confidence": 0.8
              }
            ]
            ```
            Done.
            """)
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    #expect(output.autoCreated.count == 1)
    #expect(output.autoCreated.first?.title == "Send the deck")
    #expect(output.lowConfidence.isEmpty)
}

@MainActor
@Test func actionItemsStagePrefersFencedJSONOverProseBrackets() async throws {
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
            Here are [draft] items:
            ```json
            [
              {
                "text": "Send the deck",
                "assigneeHint": "Me",
                "dueHint": null,
                "confidence": 0.8
              }
            ]
            ```
            Thanks [ok]
            """)
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    #expect(output.autoCreated.count == 1)
    #expect(output.autoCreated.first?.title == "Send the deck")
}

@MainActor
@Test func actionItemsStageIsIdempotentAcrossReruns() async throws {
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
                "dueHint": null,
                "confidence": 0.8
              }
            ]
            """)
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let first = try await stage.run(meeting: meeting, transcript: "...", summary: "...")
    let second = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    let firstTask = try #require(first.autoCreated.first)
    let secondTask = try #require(second.autoCreated.first)
    #expect(firstTask.id == secondTask.id)

    let externalSourceID = try #require(firstTask.externalSourceID)
    #expect(secondTask.externalSourceID == externalSourceID)
    let descriptor = FetchDescriptor<TaskItem>(
        predicate: #Predicate { task in
            task.externalSourceID == externalSourceID && task.deletedAt == nil
        }
    )
    #expect(try context.fetch(descriptor).count == 1)

    let updated = try #require(try meetingRepository.find(id: meeting.id))
    #expect(updated.actionItemIDs == [firstTask.id])

    let links = try linkRepository.outgoing(from: (.meeting, meeting.id)).filter { link in
        link.linkKind == .actionItem && link.toID == firstTask.id
    }
    #expect(links.count == 1)
}

@MainActor
// swiftlint:disable:next function_body_length
@Test func actionItemsStageReusesTasksWhenResponseOrderChanges() async throws {
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

    let router = SequenceActionItemsRouter(
        texts: [
            """
            [
              {
                "text": "Send deck",
                "assigneeHint": "Me",
                "dueHint": null,
                "confidence": 0.9
              }
            ]
            """,
            """
            [
              {
                "text": "Book room",
                "assigneeHint": "Me",
                "dueHint": null,
                "confidence": 0.9
              },
              {
                "text": "Send deck",
                "assigneeHint": "Me",
                "dueHint": null,
                "confidence": 0.9
              }
            ]
            """,
        ]
    )
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let first = try await stage.run(meeting: meeting, transcript: "...", summary: "...")
    let firstSendTask = try #require(first.autoCreated.first)
    let originalSendID = firstSendTask.id

    let second = try await stage.run(meeting: meeting, transcript: "...", summary: "...")
    let secondSendTask = try #require(second.autoCreated.first { $0.title == "Send deck" })
    let bookTask = try #require(second.autoCreated.first { $0.title == "Book room" })

    #expect(secondSendTask.id == originalSendID)
    #expect(secondSendTask.title == "Send deck")
    #expect(bookTask.id != originalSendID)

    let tasks = try context.fetch(FetchDescriptor<TaskItem>()).filter { $0.deletedAt == nil }
    #expect(tasks.count == 2)
    #expect(tasks.filter { $0.title == "Send deck" }.count == 1)
    #expect(tasks.filter { $0.title == "Book room" }.count == 1)

    let updated = try #require(try meetingRepository.find(id: meeting.id))
    #expect(Set(updated.actionItemIDs) == Set([originalSendID, bookTask.id]))
    #expect(updated.actionItemIDs.count == 2)

    let links = try linkRepository.outgoing(from: (.meeting, meeting.id)).filter { link in
        link.linkKind == .actionItem && link.toKind == .task
    }
    #expect(links.count == 2)
    #expect(Set(links.map(\.toID)) == Set([originalSendID, bookTask.id]))
}

@MainActor
@Test func actionItemsStageTreatsBlankHighConfidenceTextAsLowConfidence() async throws {
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
                "text": "   \\n  ",
                "assigneeHint": "Me",
                "dueHint": null,
                "confidence": 0.95
              }
            ]
            """)
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    #expect(output.autoCreated.isEmpty)
    #expect(output.lowConfidence.count == 1)
    #expect(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    #expect(try meetingRepository.find(id: meeting.id)?.actionItemIDs.isEmpty == true)
    #expect(try linkRepository.outgoing(from: (.meeting, meeting.id)).isEmpty)
}

@MainActor
@Test func actionItemsStageReturnsEmptyOutputForInvalidOrMissingJSON() async throws {
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

    let router = StubActionItemsRouter(text: "No concrete action items.")
    let stage = ActionItemsStage(
        router: router,
        taskRepository: taskRepository,
        meetingRepository: meetingRepository,
        linkRepository: linkRepository,
        sourceID: "meetings.action-items"
    )

    let output = try await stage.run(meeting: meeting, transcript: "...", summary: "...")

    #expect(output.autoCreated.isEmpty)
    #expect(output.lowConfidence.isEmpty)
    #expect(try meetingRepository.find(id: meeting.id)?.actionItemIDs.isEmpty == true)
    #expect(try linkRepository.outgoing(from: (.meeting, meeting.id)).isEmpty)
}

private actor StubActionItemsRouter: MeetingProcessingRouting {
    private let text: String
    private(set) var capturedRequest: AIRequest?

    init(text: String) {
        self.text = text
    }

    func route(_ request: AIRequest) async throws -> AIResponse {
        capturedRequest = request
        return AIResponse(text: text, providerUsed: .appleIntelligence)
    }
}

private actor SequenceActionItemsRouter: MeetingProcessingRouting {
    private var texts: [String]

    init(texts: [String]) {
        self.texts = texts
    }

    func route(_ request: AIRequest) async throws -> AIResponse {
        let text = texts.isEmpty ? "[]" : texts.removeFirst()
        return AIResponse(text: text, providerUsed: .appleIntelligence)
    }
}
