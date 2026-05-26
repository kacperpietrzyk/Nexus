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
            "Wszystkie"
        case .thisWeek:
            "Ten tydzień"
        case .hasActions:
            "Z zadaniami"
        case .imported:
            "Z importu"
        }
    }
}

@MainActor
public final class MeetingsListViewModel: ObservableObject {
    @Published public var items: [Meeting] = []
    @Published public var filter: MeetingsFilter = .all
    @Published public var searchQuery: String = ""

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
            items = try repository.allChronological().filter { meeting in
                meeting.deletedAt == nil && matchesSearch(meeting) && matchesFilter(meeting)
            }
        } catch {
            items = []
        }
    }

    private func matchesSearch(_ meeting: Meeting) -> Bool {
        let query = searchQuery.lowercased()
        guard !query.isEmpty else { return true }

        return meeting.title.lowercased().contains(query)
            || meeting.transcriptText.lowercased().contains(query)
            || meeting.summaryText.lowercased().contains(query)
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
