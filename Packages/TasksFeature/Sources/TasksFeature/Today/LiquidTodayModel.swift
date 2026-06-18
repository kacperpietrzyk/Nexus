import Foundation
import NexusCore
import NexusUI
import Observation
import SwiftData

// MARK: - Cross-module value DTOs (composed in the app layer)

/// Meeting Intelligence snapshot for the Today screen
/// (`docs/05_MODULE_TODAY.md` §Meeting Intelligence). TasksFeature never
/// imports NexusMeetings — the app layer fetches the most recent processed
/// meeting and hands this plain value across the module seam, mirroring the
/// `meetingsContent: (() -> AnyView)?` injection the old `TodayDashboard` used.
public struct LiquidTodayMeetingIntel: Equatable, Sendable {
    public let title: String
    public let occurredAt: Date
    public let durationSec: Int
    public let summary: String
    /// Decisions parsed from the meeting's summary (the app layer runs
    /// `MeetingSummarySections.parse` — TasksFeature still never imports
    /// NexusMeetings). Empty when the summary carries no decisions section.
    public let decisions: [String]
    public let actionItemCount: Int
    public let statusLabel: String

    public init(
        title: String,
        occurredAt: Date,
        durationSec: Int,
        summary: String,
        decisions: [String] = [],
        actionItemCount: Int,
        statusLabel: String
    ) {
        self.title = title
        self.occurredAt = occurredAt
        self.durationSec = durationSec
        self.summary = summary
        self.decisions = decisions
        self.actionItemCount = actionItemCount
        self.statusLabel = statusLabel
    }
}

/// Input for the injected Daily Brief provider — the same counts + titles the
/// old `TodayDashboard.DigestInput.agentBriefRequest(now:)` carried, as a
/// plain value so TasksFeature does not import NexusAgent. The app layer
/// adapts it to `AgentBriefRequest`.
public struct LiquidTodayBriefInput: Equatable, Sendable {
    public let overdue: Int
    public let today: Int
    public let noDate: Int
    public let awaiting: Int
    public let firstTitles: [String]
    public let now: Date

    public init(overdue: Int, today: Int, noDate: Int, awaiting: Int, firstTitles: [String], now: Date) {
        self.overdue = overdue
        self.today = today
        self.noDate = noDate
        self.awaiting = awaiting
        self.firstTitles = firstTitles
        self.now = now
    }
}

/// Daily Brief seam: the app layer wraps `AgentBriefService` behind this
/// closure (`nil` = the agent is disabled/unavailable → the card shows its
/// empty state; the screen never fabricates a brief).
public typealias LiquidTodayBriefProvider = @MainActor (LiquidTodayBriefInput) async -> String

/// Meeting Intelligence seam: the app layer fetches from the NexusMeetings
/// store on the screen's reload cadence. `nil` = Meetings unavailable.
public typealias LiquidTodayMeetingIntelProvider = @MainActor () -> LiquidTodayMeetingIntel?

/// Focus Suggestion seam: the app layer passes
/// `SchedulingIntelligence.suggestedFocusBlocks(events:within:)` (CalendarFeature)
/// so the inspector can surface today's free gaps without a cross-module import.
public typealias LiquidTodayFocusGapProvider = @MainActor ([CalendarEvent], DateInterval) -> [DateInterval]

/// Text cleanup shared by the Today cards: model/agent output occasionally
/// carries `[[accent]]`/`[[mono]]` digest wire markers (see `DigestRenderer`)
/// or disobeys the "plain paragraphs" prompt with Markdown headings. The
/// Liquid cards render plain ink, so both are stripped before display.
enum LiquidTodayText {
    static func strippingMarkers(from text: String) -> String {
        var result = text
        // Both the wire form ([[accent]]) and the single-bracket drift the
        // model falls back into when it half-remembers the format.
        for marker in [
            "[[accent]]", "[[/accent]]", "[[mono]]", "[[/mono]]",
            "[accent]", "[/accent]", "[mono]", "[/mono]",
            "**", "__",
        ] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let stripped = line.drop(while: { $0 == "#" }).drop(while: { $0 == " " })
            if stripped.hasPrefix("* ") || stripped.hasPrefix("- ") {
                return "• " + stripped.dropFirst(2)
            }
            return String(stripped)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Row models

/// One row on the Today's Agenda timeline: a calendar event or an ACCEPTED
/// Calendar/Motion-AI `ScheduledBlock`, normalized for rendering.
public struct LiquidAgendaItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let kind: LiquidEventKind
}

/// Top Priorities section: tasks due today/overdue sharing one priority bucket.
/// Equatable over the bucket + task identity (`===` — `TaskItem` is a model
/// reference) so `ForEach`/`.animation` can diff reloads cheaply.
public struct LiquidPriorityGroup: Identifiable, Equatable {
    public let priority: TaskPriority
    public let tasks: [TaskItem]
    public var id: Int { priority.rawValue }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.priority == rhs.priority
            && lhs.tasks.count == rhs.tasks.count
            && zip(lhs.tasks, rhs.tasks).allSatisfy { $0 === $1 }
    }
}

/// Projects-card row: an active project + its real task completion ratio.
/// Equatable via model-reference identity + the value fields.
public struct LiquidProjectProgress: Identifiable, Equatable {
    public let project: Project
    public let doneCount: Int
    public let totalCount: Int
    public var id: UUID { project.id }

    /// Completed/total fraction; 0 when the project has no tasks yet.
    public var fraction: Double {
        totalCount > 0 ? Double(doneCount) / Double(totalCount) : 0
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.project === rhs.project
            && lhs.doneCount == rhs.doneCount
            && lhs.totalCount == rhs.totalCount
    }
}

/// Notes-card row: a recent note + its Link-graph degree (in + out).
/// Equatable via model-reference identity + the value field.
public struct LiquidNoteSummary: Identifiable, Equatable {
    public let note: Note
    public let linkCount: Int
    public var id: UUID { note.id }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.note === rhs.note && lhs.linkCount == rhs.linkCount
    }
}

// MARK: - Model

/// Data feed for `LiquidTodayScreen` + `TodayInspector` (Liquid redesign
/// Task 5). One shared `@Observable` instance is owned by the app shell so the
/// main column and the right inspector render the same load. Every feed is a
/// REAL store read reusing the seams the old `TodayDashboard` used:
/// `TodayQuery` buckets, `CalendarEventProviding.eventsToday`,
/// `ScheduledBlockRepository`, `ProjectRepository.archivedProjectIDs`,
/// `LinkRepository`, and plain `FetchDescriptor`s for projects/notes.
@MainActor
@Observable
public final class LiquidTodayModel {

    public private(set) var agendaItems: [LiquidAgendaItem] = []
    /// Today's visible calendar events (raw input to the focus-gap seam).
    public private(set) var events: [CalendarEvent] = []
    /// First free focus gap left in today's workday, computed during reload
    /// through the injected `LiquidTodayFocusGapProvider` — the inspector
    /// renders this stored value instead of recomputing in `body`.
    public private(set) var focusSuggestion: DateInterval?
    public private(set) var priorityGroups: [LiquidPriorityGroup] = []
    public private(set) var projects: [LiquidProjectProgress] = []
    public private(set) var notes: [LiquidNoteSummary] = []
    /// Notes linked (Link graph, either direction) to today's priority tasks.
    public private(set) var linkedNotes: [Note] = []
    public private(set) var meetingIntel: LiquidTodayMeetingIntel?
    /// First open task pinned as focus (`TaskItem.pinnedAsFocus`) — feeds the
    /// inspector Focus Timer card; `nil` → the card shows its empty state.
    public private(set) var pinnedFocusTask: TaskItem?
    public private(set) var brief: String = ""
    public private(set) var briefIsLoading = false
    public private(set) var loadError: String?
    /// Project-name lookup for task tag pills (same shape as the old
    /// `TodayDashboard.projectName(_:)` helper).
    public private(set) var projectNamesByID: [UUID: String] = [:]

    private var reloadGeneration = 0
    private var lastBriefInput: LiquidTodayBriefInput?
    /// Test-visible count of full store snapshot reads; a gated (early-return)
    /// return-navigation leaves it unchanged — drives the skip-reload tests.
    public private(set) var storeLoadCount = 0
    // Skip-redundant-reload gate provenance: day-start + calendar-visibility the
    // snapshot was built for + a dirty flag (all three match → early-return).
    private var loadedSnapshot = false
    private var loadedDayStart: Date?
    private var loadedCalendarEventsEnabled: Bool?
    private var needsReload = true
    // First-successful-load latch (never reset by the skip-reload early-return);
    // suppresses TopPrioritiesCard's cold-start placeholder before the first load.
    private var hasLoadedOnce = false
    public var isLoaded: Bool { hasLoadedOnce }

    /// Marks the held snapshot stale so the next `reload()` re-reads the store
    /// (store-change hook, scene-active, in-screen toggle/cascade mutations).
    public func markDirty() {
        needsReload = true
    }
    /// Calendar visibility preferences — held (not constructed per reload) so
    /// tests can inject a store with controlled defaults.
    private let calendarPreferencesStore: UserDefaultsCalendarPreferencesStore

    public init(calendarPreferencesStore: UserDefaultsCalendarPreferencesStore = UserDefaultsCalendarPreferencesStore()) {
        self.calendarPreferencesStore = calendarPreferencesStore
    }

    /// Reloads every card feed. Mirrors `TodayDashboard.reloadScheduleData()`'s
    /// generation guard so an overlapping reload can never interleave stale data.
    public func reload(
        modelContext: ModelContext,
        calendarProvider: any CalendarEventProviding,
        calendarEventsEnabled: Bool,
        meetingIntelProvider: LiquidTodayMeetingIntelProvider?,
        briefProvider: LiquidTodayBriefProvider?,
        focusGapProvider: LiquidTodayFocusGapProvider? = nil,
        now: Date = .now
    ) async {
        // Skip-redundant-reload gate (FIX 1): an unchanged return-navigation
        // (snapshot loaded, dirty flag clean, same day, same calendar-visibility)
        // shows the held snapshot without re-reading the store — pixel-identical.
        // markDirty (store-change/scene-active/mutation), a calendar toggle, or a
        // midnight day-rollover all bypass it and force a fresh read.
        let dayStart = Calendar.current.startOfDay(for: now)
        let snapshotStillValid =
            loadedSnapshot && !needsReload && loadedDayStart == dayStart
            && loadedCalendarEventsEnabled == calendarEventsEnabled
        if snapshotStillValid { return }

        reloadGeneration += 1
        let generation = reloadGeneration

        // Calendar events honor the same "Read calendars" visibility toggle the
        // old Today rail applied (`TodayDashboard.calendarEvents`).
        var fetchedEvents: [CalendarEvent] = []
        if calendarEventsEnabled {
            let raw = (try? await calendarProvider.eventsToday(now: now)) ?? []
            fetchedEvents = calendarPreferencesStore.load().visibleEvents(raw)
        }

        guard generation == reloadGeneration else { return }
        let focusGap = Self.suggestedFocusGap(events: fetchedEvents, provider: focusGapProvider, now: now)

        do {
            let snapshot = try Self.loadStoreSnapshot(modelContext: modelContext, now: now)
            storeLoadCount += 1
            // Record snapshot provenance + clear the dirty flag so the next
            // unchanged return-navigation hits the early-return above.
            loadedSnapshot = true
            hasLoadedOnce = true
            loadedDayStart = dayStart
            loadedCalendarEventsEnabled = calendarEventsEnabled
            needsReload = false
            events = fetchedEvents
            focusSuggestion = focusGap
            agendaItems = Self.agendaItems(events: fetchedEvents, blocks: snapshot.acceptedBlocks)
            priorityGroups = Self.priorityGroups(overdue: snapshot.overdue, today: snapshot.today)
            projects = snapshot.projects
            notes = snapshot.notes
            linkedNotes = snapshot.linkedNotes
            pinnedFocusTask = snapshot.pinnedFocusTask
            projectNamesByID = snapshot.projectNamesByID
            meetingIntel = meetingIntelProvider?()
            loadError = nil
            await loadBriefIfNeeded(input: snapshot.briefInput, provider: briefProvider, generation: generation)
        } catch {
            guard generation == reloadGeneration else { return }
            events = fetchedEvents
            focusSuggestion = focusGap
            agendaItems = []
            priorityGroups = []
            projects = []
            notes = []
            linkedNotes = []
            pinnedFocusTask = nil
            loadError = String(describing: error)
        }
    }

    /// Next upcoming agenda item (start strictly after `now`) — feeds Up Next.
    public func upNextItem(now: Date = .now) -> LiquidAgendaItem? {
        agendaItems
            .filter { !$0.isAllDay && $0.start > now }
            .min { $0.start < $1.start }
    }

    // MARK: - Focus gap

    /// Workday window for the Focus Suggestion gap search: a standard
    /// 08:00–18:00 day (the design references morning→evening focus gaps;
    /// no workday token exists). The remaining window is clamped to `now`.
    static let workdayStartHour = 8
    static let workdayEndHour = 18

    /// First ≥1 h free gap between `now` and the end of the workday, via the
    /// injected `SchedulingIntelligence` seam over today's loaded events.
    static func suggestedFocusGap(
        events: [CalendarEvent],
        provider: LiquidTodayFocusGapProvider?,
        now: Date
    ) -> DateInterval? {
        guard let provider else { return nil }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard
            let workStart = calendar.date(byAdding: .hour, value: workdayStartHour, to: dayStart),
            let workEnd = calendar.date(byAdding: .hour, value: workdayEndHour, to: dayStart)
        else { return nil }
        let start = max(now, workStart)
        guard start < workEnd else { return nil }
        return provider(events, DateInterval(start: start, end: workEnd)).first
    }

    // MARK: - Brief

    /// Pure regeneration decision: skip only when the input is unchanged AND a
    /// non-empty brief is already held (the agent service additionally caches
    /// per (day, counts, titles) upstream). Extracted static so the dedup rule
    /// is unit-testable without driving the async provider.
    static func shouldRegenerateBrief(
        lastInput: LiquidTodayBriefInput?,
        newInput: LiquidTodayBriefInput,
        currentBrief: String
    ) -> Bool {
        !(lastInput == newInput && !currentBrief.isEmpty)
    }

    private func loadBriefIfNeeded(
        input: LiquidTodayBriefInput,
        provider: LiquidTodayBriefProvider?,
        generation: Int
    ) async {
        guard let provider else {
            brief = ""
            briefIsLoading = false
            return
        }
        guard Self.shouldRegenerateBrief(lastInput: lastBriefInput, newInput: input, currentBrief: brief) else {
            return
        }
        briefIsLoading = true
        let text = await provider(input)
        guard generation == reloadGeneration else { return }
        brief = text
        lastBriefInput = input
        briefIsLoading = false
    }

    // MARK: - Store snapshot

    private struct StoreSnapshot {
        let overdue: [TaskItem]
        let today: [TaskItem]
        let acceptedBlocks: [ScheduledBlock]
        let projects: [LiquidProjectProgress]
        let notes: [LiquidNoteSummary]
        let linkedNotes: [Note]
        let pinnedFocusTask: TaskItem?
        let projectNamesByID: [UUID: String]
        let briefInput: LiquidTodayBriefInput
    }

    private static func loadStoreSnapshot(modelContext: ModelContext, now: Date) throws -> StoreSnapshot {
        let query = TodayQuery()
        let linkRepository = LinkRepository(context: modelContext)
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []

        let overdue = try query.overdue(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let today = try query.today(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let noDate = try query.noDate(excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let awaiting = try query.awaiting(now: now, modelContext: modelContext, linkRepository: linkRepository)

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // Spec §Today's Agenda: events + ACCEPTED Motion-AI blocks (proposed
        // ones are calendar-surface concerns, not the day's committed agenda).
        let acceptedBlocks = ((try? ScheduledBlockRepository(context: modelContext).blocks(from: dayStart, to: dayEnd)) ?? [])
            .filter { $0.deletedAt == nil && $0.status == .accepted }

        let allProjects = try modelContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)]))
        let liveProjects = allProjects.filter { $0.deletedAt == nil && $0.archivedAt == nil }
        let projectNamesByID = Dictionary(
            liveProjects.map { ($0.id, $0.name) },
            uniquingKeysWith: { current, _ in current }
        )
        let rawProgress = try projectProgress(
            activeProjects: liveProjects.filter { $0.status == .active },
            modelContext: modelContext
        )
        let progressByID = Dictionary(rawProgress.map { ($0.project.id, $0) }, uniquingKeysWith: { a, _ in a })
        let projects = Self.selectTodayProjects(rawProgress.map(\.project))
            .compactMap { progressByID[$0.id] }

        let notes = try recentNotes(modelContext: modelContext, linkRepository: linkRepository)
        let linkedNotes = try linkedNotes(
            tasks: overdue + today,
            modelContext: modelContext,
            linkRepository: linkRepository
        )
        let pinned = try pinnedFocusTask(modelContext: modelContext)

        let briefInput = LiquidTodayBriefInput(
            overdue: overdue.count,
            today: today.count,
            noDate: noDate.count,
            awaiting: awaiting.count,
            firstTitles: Array(today.prefix(3).map(\.title)),
            now: now
        )

        return StoreSnapshot(
            overdue: overdue,
            today: today,
            acceptedBlocks: acceptedBlocks,
            projects: projects,
            notes: notes,
            linkedNotes: linkedNotes,
            pinnedFocusTask: pinned,
            projectNamesByID: projectNamesByID,
            briefInput: briefInput
        )
    }

    /// Pinned-first then most recently updated notes (cap 4, spec §Notes & Knowledge)
    /// with their Link-graph degree (outgoing + backlinks — both already-indexed reads).
    ///
    /// Fetch strategy: we union pinned notes with the 24 most-recent non-pinned so
    /// that a pinned note older than the top-4-by-updatedAt is never silently dropped.
    /// `selectTodayNotes` applies the final pinned-first ordering + cap.
    private static func recentNotes(
        modelContext: ModelContext,
        linkRepository: LinkRepository
    ) throws -> [LiquidNoteSummary] {
        // Fetch pinned candidates.
        let pinnedDescriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isPinned == true }
        )
        let pinned = try modelContext.fetch(pinnedDescriptor)

        // Fetch recent (non-pinned) candidates — generous cap so pinned can't be
        // crowded out; the selector trims to 4 after merging.
        var recentDescriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isPinned == false },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 24
        let recent = try modelContext.fetch(recentDescriptor)

        let notes = selectTodayNotes(pinned + recent)
        let noteIDs = notes.map(\.id)
        // Batched link reads: two fetches total instead of two per note.
        let outgoingByNote = (try? linkRepository.outgoing(fromKind: .note, fromIDs: noteIDs)) ?? [:]
        let incomingByNote = (try? linkRepository.backlinks(toKind: .note, toIDs: noteIDs)) ?? [:]
        return notes.map { note in
            let outgoing = outgoingByNote[note.id]?.count ?? 0
            let incoming = incomingByNote[note.id]?.count ?? 0
            return LiquidNoteSummary(note: note, linkCount: outgoing + incoming)
        }
    }

    /// Notes connected to today's priority tasks through the Link graph, in
    /// either direction (task→note or note→task), newest first, capped at 3.
    private static func linkedNotes(
        tasks: [TaskItem],
        modelContext: ModelContext,
        linkRepository: LinkRepository
    ) throws -> [Note] {
        var noteIDs: Set<UUID> = []
        // Cap the walk: the inspector card shows 3 notes; a dozen tasks of
        // link reads is plenty and keeps reloads cheap. Two batched fetches
        // over the capped task set replace the per-task outgoing+backlinks pair.
        let walkTaskIDs = tasks.prefix(12).map(\.id)
        let outgoingByTask = (try? linkRepository.outgoing(fromKind: .task, fromIDs: walkTaskIDs)) ?? [:]
        let incomingByTask = (try? linkRepository.backlinks(toKind: .task, toIDs: walkTaskIDs)) ?? [:]
        for taskID in walkTaskIDs {
            for link in outgoingByTask[taskID] ?? [] where link.toKind == .note {
                noteIDs.insert(link.toID)
            }
            for link in incomingByTask[taskID] ?? [] where link.fromKind == .note {
                noteIDs.insert(link.fromID)
            }
        }
        guard !noteIDs.isEmpty else { return [] }
        // Bounded fetch: predicate on the collected IDs + fetchLimit, instead
        // of scanning the whole Note table and filtering in memory.
        let idArray = Array(noteIDs)
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { idArray.contains($0.id) && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 3
        return try modelContext.fetch(descriptor)
    }

    /// First open pinned-as-focus task (earliest due first) — the same
    /// `pinnedAsFocus` flag the ⌘. focus command and the old NowCard read.
    private static func pinnedFocusTask(modelContext: ModelContext) throws -> TaskItem? {
        let openStatus = TaskStatus.open.rawValue
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.statusRaw == openStatus && $0.pinnedAsFocus == true
                    && $0.isTemplate == false
            },
            sortBy: [SortDescriptor(\.dueAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

}
