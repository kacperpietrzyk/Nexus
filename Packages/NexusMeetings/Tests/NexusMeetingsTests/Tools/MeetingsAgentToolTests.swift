import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
struct MeetingsRecentToolTests {
    @Test func returnsLastNMeetings() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        for offset in 0..<5 {
            try repo.insert(
                MeetingsTestSupport.meeting(
                    title: "M\(offset)",
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 3_600),
                    summary: String(repeating: "s", count: 240)
                )
            )
        }

        let result = try await MeetingsRecentTool(repository: repo).call(
            args: .object(["limit": .int(3)]),
            context: agentContext(modelContext: context)
        )
        let meetings = try #require(result["meetings"]?.arrayValue)

        #expect(meetings.count == 3)
        #expect(meetings.first?["title"]?.stringValue == "M4")
        #expect(meetings.first?["summaryExcerpt"]?.stringValue?.count == 200)
    }

    @Test func softDeletedNewestMeetingsDoNotConsumeRecentLimit() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        try repo.insert(MeetingsTestSupport.meeting(title: "Live 1", startedAt: base))
        try repo.insert(MeetingsTestSupport.meeting(title: "Live 2", startedAt: base.addingTimeInterval(3_600)))
        let deletedNewest = MeetingsTestSupport.meeting(
            title: "Deleted newest",
            startedAt: base.addingTimeInterval(7_200)
        )
        deletedNewest.deletedAt = base.addingTimeInterval(7_300)
        try repo.insert(deletedNewest)

        let result = try await MeetingsRecentTool(repository: repo).call(
            args: .object(["limit": .int(2)]),
            context: agentContext(modelContext: context)
        )
        let meetings = try #require(result["meetings"]?.arrayValue)

        #expect(meetings.map { $0["title"]?.stringValue } == ["Live 2", "Live 1"])
    }
}

@MainActor
struct MeetingsGetSummaryToolTests {
    @Test func returnsMarkdown() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let meeting = MeetingsTestSupport.meeting(summary: "## TL;DR\nKrotko")
        try repo.insert(meeting)

        let result = try await MeetingsGetSummaryTool(repository: repo).call(
            args: .object(["meetingID": .string(meeting.id.uuidString)]),
            context: agentContext(modelContext: context)
        )

        #expect(result["meetingID"]?.stringValue == meeting.id.uuidString)
        #expect(result["summary"]?.stringValue?.contains("TL;DR") == true)
    }
}

@MainActor
struct MeetingsGetTranscriptToolTests {
    @Test func includesSegmentsWhenRequested() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "A", text: "hello")
        ]
        let meeting = Meeting(
            title: "Transcript",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectionSource: .manual,
            transcriptText: "A: hello",
            segmentsJSON: try MeetingSpeakerSegment.encode(segments)
        )
        try repo.insert(meeting)

        let result = try await MeetingsGetTranscriptTool(repository: repo).call(
            args: .object([
                "meetingID": .string(meeting.id.uuidString),
                "includeSegments": .bool(true),
            ]),
            context: agentContext(modelContext: context)
        )
        let returnedSegments = try #require(result["segments"]?.arrayValue)

        #expect(result["transcript"]?.stringValue == "A: hello")
        #expect(returnedSegments.count == 1)
        #expect(returnedSegments.first?["speaker"]?.stringValue == "A")
    }
}

@MainActor
struct MeetingsActionItemsToolTests {
    @Test func returnsLinkedNonDeletedTasks() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let meetingRepo = MeetingRepository(context: context)
        let taskRepo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let linkRepo = LinkRepository(context: context)
        let meeting = MeetingsTestSupport.meeting(title: "Planning")
        let visibleTask = TaskItem(title: "Send notes")
        let deletedTask = TaskItem(title: "Deleted")
        try meetingRepo.insert(meeting)
        try taskRepo.insert(visibleTask)
        try taskRepo.insert(deletedTask)
        try taskRepo.softDelete(deletedTask)
        try linkRepo.findOrCreate(from: (.meeting, meeting.id), to: (.task, visibleTask.id), linkKind: .actionItem)
        try linkRepo.findOrCreate(from: (.meeting, meeting.id), to: (.task, deletedTask.id), linkKind: .actionItem)

        let result = try await MeetingsActionItemsForMeetingTool(
            meetingRepository: meetingRepo,
            taskRepository: taskRepo,
            linkRepository: linkRepo
        ).call(
            args: .object(["meetingID": .string(meeting.id.uuidString)]),
            context: agentContext(modelContext: context)
        )
        let tasks = try #require(result["tasks"]?.arrayValue)

        #expect(tasks.count == 1)
        #expect(tasks.first?["title"]?.stringValue == "Send notes")
        #expect(tasks.first?["state"]?.stringValue == TaskStatus.open.rawValue)
    }
}

@MainActor
struct MeetingsSearchToolTests {
    @Test func findsTranscriptHits() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        try repo.insert(MeetingsTestSupport.meeting(title: "Weekly", transcript: "Discuss Project Aurora launch."))
        try repo.insert(MeetingsTestSupport.meeting(title: "Other", transcript: "Budget review."))

        let result = try await MeetingsSearchTool(repository: repo).call(
            args: .object(["query": .string("aurora")]),
            context: agentContext(modelContext: context)
        )
        let hits = try #require(result["hits"]?.arrayValue)

        #expect(hits.count == 1)
        #expect(hits.first?["title"]?.stringValue == "Weekly")
        #expect(hits.first?["snippet"]?.stringValue?.localizedCaseInsensitiveContains("Aurora") == true)
    }

    @Test func handlesNonASCIITranscriptSnippetRanges() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let transcript = String(repeating: "İ", count: 300) + " target " + String(repeating: "planning ", count: 30)
        try repo.insert(MeetingsTestSupport.meeting(title: "Unicode", transcript: transcript))

        let result = try await MeetingsSearchTool(repository: repo).call(
            args: .object(["query": .string("target")]),
            context: agentContext(modelContext: context)
        )
        let hits = try #require(result["hits"]?.arrayValue)

        #expect(hits.count == 1)
        #expect(hits.first?["title"]?.stringValue == "Unicode")
        #expect(hits.first?["snippet"]?.stringValue?.contains("target") == true)
    }
}

@MainActor
struct MeetingsListByDateToolTests {
    @Test func validatesRangeAndReturnsSnapshots() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try repo.insert(MeetingsTestSupport.meeting(title: "Inside", startedAt: base))
        try repo.insert(MeetingsTestSupport.meeting(title: "Outside", startedAt: base.addingTimeInterval(86_400)))

        let result = try await MeetingsListByDateTool(repository: repo).call(
            args: .object([
                "from": .string("2023-11-14T00:00:00Z"),
                "to": .string("2023-11-15T00:00:00Z"),
            ]),
            context: agentContext(modelContext: context)
        )
        let meetings = try #require(result["meetings"]?.arrayValue)

        #expect(meetings.map { $0["title"]?.stringValue } == ["Inside"])
    }
}

@MainActor
private func agentContext(modelContext: ModelContext) -> AgentContext {
    let taskRepository = TaskItemRepository(context: modelContext, scheduler: RRuleScheduler(), now: { .now })
    return AgentContext(
        modelContext: ModelContextRef(modelContext),
        taskRepository: TaskItemRepositoryRef(taskRepository),
        searchIndex: SearchIndex(),
        now: { .now }
    )
}
