import Foundation
import NexusAI
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
@Suite("LiquidMeetingsModel")
struct LiquidMeetingsModelTests {

    // MARK: - Grouping

    private static let noon = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func bucketsMeetingsByStartedAt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Self.noon

        let today = MeetingsTestSupport.meeting(title: "Today", startedAt: now.addingTimeInterval(-3600))
        let upcoming = MeetingsTestSupport.meeting(title: "Upcoming", startedAt: now.addingTimeInterval(7200))
        let yesterday = MeetingsTestSupport.meeting(
            title: "Yesterday", startedAt: now.addingTimeInterval(-86_400))
        let lastMonth = MeetingsTestSupport.meeting(
            title: "Old", startedAt: now.addingTimeInterval(-86_400 * 30))

        let groups = LiquidMeetingsModel.grouped(
            [upcoming, today, yesterday, lastMonth], now: now, calendar: calendar)

        #expect(groups.map(\.bucket) == [.today, .yesterday, .earlier])
        // Upcoming meetings stay visible, sorted into Today.
        #expect(groups[0].meetings.map(\.title) == ["Upcoming", "Today"])
        #expect(groups[1].meetings.map(\.title) == ["Yesterday"])
        #expect(groups[2].meetings.map(\.title) == ["Old"])
    }

    @Test func emptyBucketsAreDropped() {
        let calendar = Calendar(identifier: .gregorian)
        let groups = LiquidMeetingsModel.grouped([], now: Self.noon, calendar: calendar)
        #expect(groups.isEmpty)
    }

    // MARK: - Reload feeds

    @Test func reloadResolvesDetailKnowledgeAndNextMeeting() throws {
        let harness = try Harness()
        let now = Self.noon

        let meeting = MeetingsTestSupport.meeting(
            title: "Harmony sync",
            startedAt: now.addingTimeInterval(-3600),
            status: .ready,
            transcript: "alpha beta gamma",
            summary: "## TL;DR\nShipped.\n\n## Decisions\n- Go live Friday"
        )
        let upcoming = MeetingsTestSupport.meeting(
            title: "Planning", startedAt: now.addingTimeInterval(7200))
        try harness.composition.meetingRepository.insert(meeting)
        try harness.composition.meetingRepository.insert(upcoming)

        // Action item task: linked via actionItemIDs AND the Link graph —
        // must show as an action item but NOT as a "Linked to" row.
        let action = TaskItem(title: "Ship the build")
        // A directly linked note plus a 2-hop note (note linked to the task).
        let direct = Note(title: "Launch notes")
        let related = Note(title: "Risk register")
        harness.context.insert(action)
        harness.context.insert(direct)
        harness.context.insert(related)
        try harness.context.save()

        meeting.actionItemIDs = [action.id]
        try harness.composition.meetingRepository.upsert(meeting)
        try harness.composition.linkRepository.create(
            from: (.meeting, meeting.id), to: (.task, action.id), linkKind: .actionItem)
        try harness.composition.linkRepository.create(
            from: (.meeting, meeting.id), to: (.note, direct.id), linkKind: .mentions)
        try harness.composition.linkRepository.create(
            from: (.note, related.id), to: (.task, action.id), linkKind: .mentions)

        let model = LiquidMeetingsModel()
        model.reload(composition: harness.composition, selectedID: meeting.id, now: now)

        #expect(model.loadError == nil)
        #expect(model.meetings.map(\.title) == ["Planning", "Harmony sync"])
        #expect(model.nextMeeting?.title == "Planning")
        #expect(model.sections.overview == "Shipped.")
        #expect(model.sections.decisions == ["Go live Friday"])
        #expect(model.actionItems.map(\.title) == ["Ship the build"])
        // Linked-to excludes the action-item task but keeps the note.
        #expect(model.linkedItems.map(\.title) == ["Launch notes"])
        // Graph keeps every 1-hop neighbour (task + note).
        #expect(Set(model.graphItems.map(\.title)) == ["Ship the build", "Launch notes"])
        // 2-hop heuristic: the note sharing the task link is related; the
        // directly linked note is not repeated.
        #expect(model.relatedNotes.map(\.title) == ["Risk register"])
        #expect(model.insights.wordCount == 3)
    }

    @Test func searchFiltersByTitle() throws {
        let harness = try Harness()
        try harness.composition.meetingRepository.insert(
            MeetingsTestSupport.meeting(title: "Harmony XDR weekly"))
        try harness.composition.meetingRepository.insert(
            MeetingsTestSupport.meeting(title: "Design review"))

        let model = LiquidMeetingsModel()
        model.searchQuery = "harmony"
        model.reload(composition: harness.composition, selectedID: nil, now: Self.noon)

        #expect(model.meetings.map(\.title) == ["Harmony XDR weekly"])
    }

    @Test func displayTitleDropsSoftDeletedTargets() throws {
        let harness = try Harness()
        let note = Note(title: "Gone")
        note.deletedAt = .now
        harness.context.insert(note)
        try harness.context.save()

        let title = LiquidMeetingsModel.displayTitle(
            kind: .note, id: note.id, context: harness.context)
        #expect(title == nil)
    }
}

// MARK: - Harness

@MainActor
private struct Harness {
    let context: ModelContext
    let composition: MeetingsComposition
    private let folder: URL

    init() throws {
        context = try MeetingsTestSupport.makeContext()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiquidMeetingsModelTests-\(UUID().uuidString)", isDirectory: true)
        composition = try MeetingsComposition(
            context: context,
            router: StubRouter(),
            rootAudioFolder: folder,
            calendarProvider: MockCalendarEventProvider()
        )
    }
}

private struct StubRouter: MeetingProcessingRouting {
    func route(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "[]", providerUsed: .appleIntelligence)
    }
}
