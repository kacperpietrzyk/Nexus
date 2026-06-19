import Foundation
import NexusCore
import Observation
import SwiftData
import TasksFeature

/// Shared data feed for the Liquid Meetings / Notes Intelligence screen
/// (Task 10, spec `liquid_productivity_design_system/docs/08_MODULE_MEETINGS_NOTES.md`).
/// One `@Observable` instance is owned by the app shell so the main column
/// (`LiquidMeetingsScreen`: list + detail + knowledge) and the right inspector
/// (`MeetingActionsInspector`) render the same load — the identical sharing
/// shape `LiquidTodayModel` / `LiquidProjectsModel` use.
///
/// Every feed is a REAL store read: live meetings via `MeetingRepository`,
/// parsed summary sections via `MeetingSummarySections.parse` (Task 9),
/// aggregate stats via `MeetingInsights`, action-item `TaskItem`s resolved
/// from `actionItemIDs`, and the knowledge column from the polymorphic `Link`
/// graph (`LinkRepository`). Nothing is fabricated — sparse graphs surface as
/// empty states.
@MainActor
@Observable
public final class LiquidMeetingsModel {

    // MARK: Value types

    /// A real participant decoded from `participantsJSON` (named speakers only —
    /// pipeline placeholder IDs like `S1` carry no display name and are skipped).
    public struct Attendee: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// Set when the user assigned this speaker to a `Person` contact.
        public let personID: UUID?
    }

    /// One resolved edge of the meeting's `Link` graph, with the target's real
    /// title. Targets that no longer resolve (deleted / unsynced) are dropped.
    public struct LinkedItem: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let kind: ItemKind
        public let targetID: UUID
        public let title: String
        public let isBacklink: Bool
    }

    public struct RelatedNote: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
    }

    /// Date buckets for the meeting list (spec §Meeting list). The spec's
    /// "Last Week" tail is collapsed into "Earlier" — the store reaches back
    /// months and a dedicated seven-day-old bucket adds noise, not signal.
    public enum Bucket: String, CaseIterable, Sendable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case earlier = "Earlier"
    }

    // MARK: List feed

    /// Live meetings (`deletedAt == nil`), newest first, filtered by
    /// `searchQuery` (case/diacritic-insensitive title match).
    public private(set) var meetings: [Meeting] = []
    /// Next upcoming meeting (`startedAt > now`), soonest first — the
    /// inspector's Next Meeting card. `nil` → calm empty state.
    public private(set) var nextMeeting: Meeting?
    public var searchQuery = ""

    // MARK: Selected-meeting feed

    public private(set) var meeting: Meeting?
    public private(set) var sections: MeetingSummarySections = .empty
    public private(set) var insights: MeetingInsights = .empty
    public private(set) var attendees: [Attendee] = []
    /// Action-item tasks resolved from `actionItemIDs`, in stored order.
    public private(set) var actionItems: [TaskItem] = []
    /// Outgoing links, excluding action-item tasks (those already have their
    /// own card — repeating them as "Linked to" rows is duplication, not links).
    public private(set) var linkedItems: [LinkedItem] = []
    /// All 1-hop neighbours (outgoing + backlinks, deduped by target) for the
    /// Backlinks mini-graph, capped at `Self.maxGraphNodes`.
    public private(set) var graphItems: [LinkedItem] = []
    /// 2-hop "related notes" — see `relatedNotes(context:)` for the heuristic.
    public private(set) var relatedNotes: [RelatedNote] = []

    // `internal(set)` so extension files can set error state without a public setter.
    public internal(set) var loadError: String?

    public init() {}

    private static let maxGraphNodes = 8
    private static let maxRelatedNotes = 5

    // MARK: - Reload

    /// Synchronous main-actor store reads; the screen calls this from `.task`
    /// and on store-change notifications, mirroring the other Liquid models.
    public func reload(composition: MeetingsComposition, selectedID: UUID?, now: Date = .now) {
        do {
            // Synced Meeting UUIDs are not unique (CloudKit forbids
            // @Attribute(.unique); the live store carries real duplicate-id
            // rows). Dedup keep-first — the same shape ActionItemsTabView
            // uses for tasks — so list identity (`ForEach(id: \.id)`) holds.
            var seen = Set<UUID>()
            let all = try composition.meetingRepository.allChronological()
                .filter { $0.deletedAt == nil && seen.insert($0.id).inserted }
            meetings = filtered(all, query: searchQuery)
            nextMeeting = all.filter { $0.startedAt > now }.min { $0.startedAt < $1.startedAt }
            try loadDetail(composition: composition, selectedID: selectedID, all: all)
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    private func loadDetail(
        composition: MeetingsComposition, selectedID: UUID?, all: [Meeting]
    ) throws {
        guard let selectedID, let selected = all.first(where: { $0.id == selectedID }) else {
            meeting = nil
            sections = .empty
            insights = .empty
            attendees = []
            actionItems = []
            linkedItems = []
            graphItems = []
            relatedNotes = []
            return
        }
        meeting = selected
        sections = MeetingSummarySections.parse(summaryText: selected.summaryText)
        let segments = (try? MeetingSpeakerSegment.decode(selected.segmentsJSON)) ?? []
        let participants =
            selected.participantsJSON
            .flatMap { try? MeetingParticipant.decode($0) } ?? []
        var speakerNames: [String: String] = [:]
        for participant in participants {
            let name = participant.displayName.trimmingCharacters(in: .whitespaces)
            let sid = participant.speakerID.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != sid else { continue }
            speakerNames[canonicalSpeakerKey(participant.speakerID)] = name
        }
        insights = MeetingInsights.insights(
            durationSec: selected.durationSec > 0 ? selected.durationSec : nil,
            segments: segments,
            transcriptText: selected.transcriptText,
            speakerNames: speakerNames
        )
        attendees = Self.attendees(of: selected)
        actionItems = Self.actionItems(of: selected, context: composition.meetingRepository.context)
        try loadKnowledge(composition: composition, meeting: selected)
    }

    // MARK: - List helpers

    private func filtered(_ all: [Meeting], query: String) -> [Meeting] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Groups `meetings` into the spec's list sections by `startedAt`,
    /// dropping empty buckets. Pure + injectable clock for tests. Meetings
    /// later than `now` (the upcoming ones) sort into Today so they stay
    /// visible in the list.
    public static func grouped(
        _ meetings: [Meeting], now: Date = .now, calendar: Calendar = .current
    ) -> [(bucket: Bucket, meetings: [Meeting])] {
        var byBucket: [Bucket: [Meeting]] = [:]
        for meeting in meetings {
            byBucket[bucket(for: meeting.startedAt, now: now, calendar: calendar), default: []]
                .append(meeting)
        }
        return Bucket.allCases.compactMap { bucket in
            guard let items = byBucket[bucket], !items.isEmpty else { return nil }
            return (bucket, items)
        }
    }

    static func bucket(for date: Date, now: Date, calendar: Calendar) -> Bucket {
        if date > now || calendar.isDate(date, inSameDayAs: now) { return .today }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        if let yesterday, calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
        return .earlier
    }

    // MARK: - Detail helpers

    private static func attendees(of meeting: Meeting) -> [Attendee] {
        guard let data = meeting.participantsJSON,
            let participants = try? MeetingParticipant.decode(data)
        else { return [] }
        return
            participants
            .filter { !$0.displayName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Attendee(id: $0.speakerID, name: $0.displayName, personID: $0.personID) }
    }

    private static func actionItems(of meeting: Meeting, context: ModelContext) -> [TaskItem] {
        let ids = meeting.actionItemIDs
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in ids.contains(task.id) && task.deletedAt == nil }
        )
        guard let fetched = try? context.fetch(descriptor) else { return [] }
        // Synced TaskItem ids are not unique (CloudKit forbids @Attribute(.unique));
        // dedup keep-first — the same shape ActionItemsTabView uses.
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        return ids.compactMap { byID[$0] }
    }

    /// Open (not yet completed) action items, for the inspector's Follow-up card.
    public var openActionItems: [TaskItem] { actionItems.filter { $0.status != .done } }

    // MARK: - Mutations

    /// Pins or unpins a meeting so it surfaces in the Today view.
    public func togglePin(_ meeting: Meeting, composition: MeetingsComposition) {
        do {
            try composition.meetingRepository.setPinned(meeting, !meeting.isPinned)
        } catch {
            loadError = String(describing: error)
        }
    }

    /// Completes / reopens an action item through the real task repository —
    /// the same `TaskCompletionAction` path the rest of the app uses (cascade
    /// fallback for parents with open subtasks; non-interactive surface).
    public func toggleActionItem(_ task: TaskItem, composition: MeetingsComposition) {
        do {
            if task.status == .done {
                try composition.taskItemRepository.reopen(task)
            } else {
                try TaskCompletionAction.completeOrCascade(task, repository: composition.taskItemRepository)
            }
        } catch {
            loadError = String(describing: error)
        }
    }

    // MARK: - Knowledge graph

    private func loadKnowledge(composition: MeetingsComposition, meeting: Meeting) throws {
        let context = composition.meetingRepository.context
        let endpoint: (ItemKind, UUID) = (.meeting, meeting.id)
        let outgoing = try composition.linkRepository.outgoing(from: endpoint)
        let backlinks = try composition.linkRepository.backlinks(to: endpoint)
        let actionItemIDs = Set(meeting.actionItemIDs)

        let outgoingItems = resolve(
            links: outgoing, isBacklink: false, context: context, meetingID: meeting.id)
        let backlinkItems = resolve(
            links: backlinks, isBacklink: true, context: context, meetingID: meeting.id)

        linkedItems = outgoingItems.filter { !($0.kind == .task && actionItemIDs.contains($0.targetID)) }

        var seenTargets = Set<UUID>()
        graphItems = (outgoingItems + backlinkItems)
            .filter { seenTargets.insert($0.targetID).inserted }
            .prefix(Self.maxGraphNodes)
            .map { $0 }

        relatedNotes = computeRelatedNotes(
            neighbours: outgoingItems + backlinkItems,
            directNoteIDs: Set((outgoingItems + backlinkItems).filter { $0.kind == .note }.map(\.targetID)),
            composition: composition
        )
    }

    /// Resolves `Link` edges to displayable rows; the far endpoint of each
    /// edge is title-resolved per kind and unresolvable targets are dropped.
    private func resolve(
        links: [Link], isBacklink: Bool, context: ModelContext, meetingID: UUID
    ) -> [LinkedItem] {
        links.compactMap { link in
            let kind = isBacklink ? link.fromKind : link.toKind
            let targetID = isBacklink ? link.fromID : link.toID
            guard targetID != meetingID else { return nil }
            guard let title = Self.displayTitle(kind: kind, id: targetID, context: context) else {
                return nil
            }
            return LinkedItem(
                id: link.id, kind: kind, targetID: targetID, title: title, isBacklink: isBacklink)
        }
    }

    /// Honest "related notes" heuristic, documented per the module spec:
    /// `Meeting` has no tags field, so tag overlap can't apply meeting-side.
    /// Instead this walks the Link graph two hops — notes connected (either
    /// direction) to any of the meeting's direct neighbours (tasks, projects,
    /// people, notes) count as related. Directly linked notes are excluded
    /// (they're already "Linked to" rows), output is deduped and capped.
    private func computeRelatedNotes(
        neighbours: [LinkedItem], directNoteIDs: Set<UUID>, composition: MeetingsComposition
    ) -> [RelatedNote] {
        let context = composition.meetingRepository.context
        var seen = Set<UUID>()
        var results: [RelatedNote] = []
        for neighbour in neighbours {
            let endpoint: (ItemKind, UUID) = (neighbour.kind, neighbour.targetID)
            let edges =
                ((try? composition.linkRepository.outgoing(from: endpoint)) ?? [])
                + ((try? composition.linkRepository.backlinks(to: endpoint)) ?? [])
            for edge in edges {
                for (kind, id) in [(edge.fromKind, edge.fromID), (edge.toKind, edge.toID)]
                where kind == .note && !directNoteIDs.contains(id) && seen.insert(id).inserted {
                    if let title = Self.displayTitle(kind: .note, id: id, context: context) {
                        results.append(RelatedNote(id: id, title: title))
                    }
                }
                if results.count >= Self.maxRelatedNotes { return results }
            }
        }
        return results
    }

    /// Real title of a graph endpoint, fetched per kind; `nil` for soft-deleted
    /// or missing targets and for kinds with no user-facing surface here.
    /// Concrete per-kind predicates on purpose: a generic `#Predicate` over a
    /// protocol-constrained type traps under `-O` (see the Release smoke rule).
    static func displayTitle(kind: ItemKind, id: UUID, context: ModelContext) -> String? {
        switch kind {
        case .note:
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let note = try? context.fetch(descriptor).first, note.deletedAt == nil
            else { return nil }
            return note.title.isEmpty ? "Untitled note" : note.title
        case .task:
            var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let task = try? context.fetch(descriptor).first, task.deletedAt == nil
            else { return nil }
            return task.title
        case .project:
            var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let project = try? context.fetch(descriptor).first, project.deletedAt == nil
            else { return nil }
            return project.name
        case .person:
            var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let person = try? context.fetch(descriptor).first, person.deletedAt == nil
            else { return nil }
            return person.displayName
        case .meeting:
            var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let other = try? context.fetch(descriptor).first, other.deletedAt == nil
            else { return nil }
            return other.title
        default:
            return nil
        }
    }
}
