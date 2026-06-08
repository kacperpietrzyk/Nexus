import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

/// Speaker-aware list filtering (spec §6). The list view-model filters in-memory
/// (it composes with the date/has-actions/imported filters, which the repository's
/// `search(...,speaker:)` does not), so the speaker predicate is exercised here
/// against a real `MeetingRepository`. Render is not covered (cannot be smoked).
@MainActor
@Suite struct MeetingsListSpeakerFilterTests {
    private func seed(_ repo: MeetingRepository) throws -> (anna: UUID, ben: UUID) {
        let annaMeeting = MeetingsTestSupport.meeting(title: "Anna sync")
        annaMeeting.segmentsJSON = try MeetingSpeakerSegment.encode([
            .init(startMs: 0, endMs: 1000, speaker: "Speaker_1", text: "Ship the parser"),
            .init(startMs: 1000, endMs: 2000, speaker: "Speaker_2", text: "I will review"),
        ])
        annaMeeting.participantsJSON = try MeetingParticipant.encode([
            .init(speakerID: "Speaker_1", displayName: "Anna"),
            .init(speakerID: "Speaker_2", displayName: "Ben"),
        ])
        try repo.insert(annaMeeting)

        let benMeeting = MeetingsTestSupport.meeting(title: "Ben standup")
        benMeeting.segmentsJSON = try MeetingSpeakerSegment.encode([
            .init(startMs: 0, endMs: 1000, speaker: "Speaker_1", text: "Deploy tonight")
        ])
        benMeeting.participantsJSON = try MeetingParticipant.encode([
            .init(speakerID: "Speaker_1", displayName: "Ben")
        ])
        try repo.insert(benMeeting)

        return (annaMeeting.id, benMeeting.id)
    }

    @Test func noSpeakerFilterIsTodaysBehavior() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        _ = try seed(repo)
        let vm = MeetingsListViewModel(repository: repo)
        vm.reload()
        #expect(vm.items.count == 2)
    }

    @Test func speakerOptionsExcludeRawDiarizedTokens() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        _ = try seed(repo)
        let vm = MeetingsListViewModel(repository: repo)
        vm.reload()
        #expect(vm.speakerOptions == ["Anna", "Ben"])
    }

    @Test func speakerFilterReturnsOnlyMeetingsWhereSpeakerSpoke() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let ids = try seed(repo)
        let vm = MeetingsListViewModel(repository: repo)
        vm.speakerFilter = "Anna"
        vm.reload()
        #expect(vm.items.map(\.id) == [ids.anna])
    }

    @Test func speakerPlusQueryMatchesOnlyWithinThatSpeakersSegments() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        _ = try seed(repo)
        let vm = MeetingsListViewModel(repository: repo)

        // "review" is said by Ben, not Anna, in the Anna-sync meeting.
        vm.speakerFilter = "Anna"
        vm.searchQuery = "review"
        vm.reload()
        #expect(vm.items.isEmpty)

        // "parser" is said by Anna.
        vm.searchQuery = "parser"
        vm.reload()
        #expect(vm.items.count == 1)
    }

    @Test func speakerFilterMatchesRawTokenAndIsDiacriticInsensitive() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        let ids = try seed(repo)
        let vm = MeetingsListViewModel(repository: repo)

        // Raw diarized token resolves even without a display name mapping.
        vm.speakerFilter = "Speaker_2"
        vm.reload()
        #expect(vm.items.map(\.id) == [ids.anna])
    }

    @Test func blankSpeakerFilterIsTreatedAsNoConstraint() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        _ = try seed(repo)
        let vm = MeetingsListViewModel(repository: repo)
        vm.speakerFilter = "   "
        vm.reload()
        #expect(vm.items.count == 2)
    }
}
