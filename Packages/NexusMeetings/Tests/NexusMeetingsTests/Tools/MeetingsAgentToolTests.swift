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

    @Test func speakerArgumentFiltersSegmentsAndImpliesInclude() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "alpha"),
            MeetingSpeakerSegment(startMs: 1_000, endMs: 2_000, speaker: "Speaker_2", text: "beta"),
        ]
        let meeting = Meeting(
            title: "Transcript",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectionSource: .manual,
            transcriptText: "Speaker_1: alpha\nSpeaker_2: beta",
            segmentsJSON: try MeetingSpeakerSegment.encode(segments),
            participantsJSON: try MeetingParticipant.encode([
                MeetingParticipant(speakerID: "Speaker_2", displayName: "Bob")
            ])
        )
        try repo.insert(meeting)

        // speaker filter implies includeSegments (no explicit flag passed) and
        // resolves the display name "Bob" → Speaker_2.
        let result = try await MeetingsGetTranscriptTool(repository: repo).call(
            args: .object([
                "meetingID": .string(meeting.id.uuidString),
                "speaker": .string("Bob"),
            ]),
            context: agentContext(modelContext: context)
        )
        let returnedSegments = try #require(result["segments"]?.arrayValue)
        #expect(returnedSegments.count == 1)
        #expect(returnedSegments.first?["speaker"]?.stringValue == "Speaker_2")
        #expect(returnedSegments.first?["text"]?.stringValue == "beta")
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

    @Test func speakerArgumentNarrowsToThatSpeaker() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "the budget is locked"),
            MeetingSpeakerSegment(startMs: 1_000, endMs: 2_000, speaker: "Speaker_2", text: "the timeline slips"),
        ]
        let meeting = Meeting(
            title: "Planning",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectionSource: .manual,
            transcriptText: "Speaker_1: the budget is locked\nSpeaker_2: the timeline slips",
            segmentsJSON: try MeetingSpeakerSegment.encode(segments)
        )
        try repo.insert(meeting)

        let tool = MeetingsSearchTool(repository: repo)

        // Speaker_1 said "budget" → hit, with a snippet drawn from their segment.
        let match = try await tool.call(
            args: .object(["query": .string("budget"), "speaker": .string("Speaker_1")]),
            context: agentContext(modelContext: context)
        )
        let matchHits = try #require(match["hits"]?.arrayValue)
        #expect(matchHits.count == 1)
        #expect(matchHits.first?["snippet"]?.stringValue?.localizedCaseInsensitiveContains("budget") == true)

        // Speaker_2 did NOT say "budget" → no hit.
        let miss = try await tool.call(
            args: .object(["query": .string("budget"), "speaker": .string("Speaker_2")]),
            context: agentContext(modelContext: context)
        )
        #expect(try #require(miss["hits"]?.arrayValue).isEmpty)
    }

    @Test func emptySpeakerArgumentBehavesAsNoFilter() async throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        // Title-only match, no segments: speaker mode would find nothing, so an
        // empty "speaker" string must normalize to nil and hit via searchableText.
        try repo.insert(MeetingsTestSupport.meeting(title: "Weekly", transcript: "Discuss Project Aurora launch."))

        let result = try await MeetingsSearchTool(repository: repo).call(
            args: .object(["query": .string("aurora"), "speaker": .string("   ")]),
            context: agentContext(modelContext: context)
        )
        let hits = try #require(result["hits"]?.arrayValue)
        #expect(hits.map { $0["title"]?.stringValue } == ["Weekly"])
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
