import Combine
import Foundation

public enum MeetingsFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case thisWeek
    case hasActions
    case imported

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all:
            "All"
        case .thisWeek:
            "This week"
        case .hasActions:
            "With action items"
        case .imported:
            "Imported"
        }
    }
}

@MainActor
public final class MeetingsListViewModel: ObservableObject {
    @Published public var items: [Meeting] = []
    @Published public var filter: MeetingsFilter = .all
    @Published public var searchQuery: String = ""
    /// Optional speaker filter (spec §6). `nil` = no speaker constraint (today's
    /// behavior). When set, a meeting matches only if that speaker has a segment,
    /// and — if a query is also present — only if the query appears *within that
    /// speaker's* segments (not the whole transcript): a hit means the named
    /// speaker actually said it. Matches the raw diarized token or the assigned
    /// `displayName` via ``MergeStage/segments(_:forSpeaker:participants:)``.
    @Published public var speakerFilter: String?
    /// Distinct labeled speaker names across all meetings, for the filter menu.
    @Published public private(set) var speakerOptions: [String] = []

    private let repository: MeetingRepository
    private let clock: () -> Date

    public init(
        repository: MeetingRepository,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.clock = clock
    }

    public func reload() {
        do {
            speakerOptions = (try? repository.distinctParticipantNames()) ?? []
            items = try repository.allChronological().filter { meeting in
                meeting.deletedAt == nil
                    && matchesSearch(meeting)
                    && matchesSpeaker(meeting)
                    && matchesFilter(meeting)
            }
        } catch {
            items = []
        }
    }

    private func matchesSearch(_ meeting: Meeting) -> Bool {
        let query = searchQuery.lowercased()
        guard !query.isEmpty else { return true }

        // With a speaker selected, the query must land inside that speaker's
        // segments (handled in `matchesSpeaker`); the broad title/summary match
        // would otherwise leak meetings where someone else said the word.
        if speakerFilter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }

        return meeting.title.lowercased().contains(query)
            || meeting.transcriptText.lowercased().contains(query)
            || meeting.summaryText.lowercased().contains(query)
    }

    private func matchesSpeaker(_ meeting: Meeting) -> Bool {
        guard let speaker = speakerFilter?.trimmingCharacters(in: .whitespacesAndNewlines),
            !speaker.isEmpty
        else {
            return true
        }

        let segments = (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? []
        let participants = (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
        let speakerSegments = MergeStage.segments(
            segments,
            forSpeaker: speaker,
            participants: participants
        )
        guard !speakerSegments.isEmpty else { return false }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return speakerSegments.contains {
            $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func matchesFilter(_ meeting: Meeting) -> Bool {
        switch filter {
        case .all:
            true
        case .thisWeek:
            meeting.startedAt >= clock().addingTimeInterval(-7 * 86_400)
        case .hasActions:
            !meeting.actionItemIDs.isEmpty
        case .imported:
            meeting.detectionSource == MeetingDetectionSource.imported.rawValue
        }
    }
}
