import Foundation
import NexusCore
import Observation
import SwiftData

/// Drives the calendar surface (spec §7 / §9 / §10): scope + anchor navigation,
/// loading events and blocks, block accept/reject/plan-day, and event CRUD via the
/// injected providers. `@MainActor @Observable` (SwiftUI binding + SwiftData
/// isolation).
///
/// All EventKit lives behind the injected protocols (`CalendarEventProviding`,
/// `CalendarEventWriting`, `CalendarListing`); the view-model is therefore testable
/// with the in-source mocks (`MockCalendarEventProvider`, `MockCalendarWriter`).
@MainActor
@Observable
public final class CalendarViewModel {
    public var scope: CalendarScope = .day
    public var anchor: Date
    public private(set) var events: [CalendarEvent] = []
    public private(set) var blocks: [ScheduledBlock] = []
    public private(set) var authorization: CalendarAuthorizationStatus
    public private(set) var overload: OverloadReport?
    public private(set) var isLoading = false
    public var lastError: String?

    private let context: ModelContext
    private let reader: any CalendarEventProviding
    private let writer: (any CalendarEventWriting)?
    private let listing: (any CalendarListing)?
    private let blockRepository: ScheduledBlockRepository
    private let reconciler: CalendarSyncReconciler?
    private let planner: DayPlanner
    private let preferencesStore: UserDefaultsCalendarPreferencesStore
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        context: ModelContext,
        reader: any CalendarEventProviding,
        writer: (any CalendarEventWriting)? = nil,
        listing: (any CalendarListing)? = nil,
        preferencesStore: UserDefaultsCalendarPreferencesStore = UserDefaultsCalendarPreferencesStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.reader = reader
        self.writer = writer
        self.listing = listing
        self.preferencesStore = preferencesStore
        self.calendar = calendar
        self.now = now
        self.anchor = now()
        self.authorization = reader.authorizationStatus()
        self.blockRepository = ScheduledBlockRepository(context: context, now: now)
        self.planner = DayPlanner(context: context)
        if let writer {
            self.reconciler = CalendarSyncReconciler(context: context, writer: writer, now: now)
        } else {
            self.reconciler = nil
        }
    }

    public var preferences: CalendarPreferences { preferencesStore.load() }

    public var hasCalendarAccess: Bool {
        authorization == .fullAccess || authorization == .writeOnly
    }

    // MARK: - Window

    /// `[start, end)` covered by the current scope+anchor.
    public var window: (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: anchor)
        switch scope {
        case .day:
            let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return (dayStart, end)
        case .week:
            let weekStart = startOfWeek(for: anchor)
            let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            return (weekStart, end)
        case .month:
            let monthStart = startOfMonth(for: anchor)
            let gridStart = startOfWeek(for: monthStart)
            let end = calendar.date(byAdding: .day, value: 42, to: gridStart) ?? gridStart
            return (gridStart, end)
        }
    }

    /// Days the current scope renders (for week/month grids).
    public var visibleDays: [Date] {
        let win = window
        var days: [Date] = []
        var cursor = win.start
        while cursor < win.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    public func step(_ direction: Int) {
        let component: Calendar.Component
        let value: Int
        switch scope {
        case .day: component = .day; value = direction
        case .week: component = .day; value = direction * 7
        case .month: component = .month; value = direction
        }
        if let next = calendar.date(byAdding: component, value: value, to: anchor) {
            anchor = next
        }
    }

    public func goToToday() { anchor = now() }

    // MARK: - Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        authorization = reader.authorizationStatus()
        let win = window
        do {
            events = try await reader.eventsBetween(start: win.start, end: win.end)
        } catch {
            events = []
            lastError = String(describing: error)
        }
        reloadBlocks()
    }

    public func reloadBlocks() {
        let win = window
        blocks = (try? blockRepository.blocks(from: win.start, to: win.end)) ?? []
    }

    /// Items laid out on the hour axis for a single `day`.
    public func timelineItems(forDay day: Date) -> [TimelineItem] {
        DayTimelineLayout.items(forDay: day, events: events, blocks: blocks, calendar: calendar)
    }

    // MARK: - Permissions

    @discardableResult
    public func requestAccess() async -> CalendarAuthorizationStatus {
        do {
            if let writer {
                authorization = try await writer.requestFullAccess()
            } else {
                authorization = try await reader.requestAccess()
            }
        } catch {
            lastError = String(describing: error)
        }
        await load()
        return authorization
    }

    // MARK: - Plan my day (spec §10)

    public func planDay(horizonDays: Int = 1) async {
        let win = window
        let fetched = (try? await reader.eventsBetween(start: win.start, end: win.end)) ?? []
        do {
            let result = try planner.planDay(
                events: fetched,
                prefs: preferences,
                now: now(),
                calendar: calendar,
                horizonDays: horizonDays
            )
            overload = result.overload
        } catch {
            lastError = String(describing: error)
        }
        reloadBlocks()
    }

    // MARK: - Block accept / reject / manual (spec §7)

    public func accept(blockID: UUID) async {
        guard let block = try? blockRepository.find(blockID) else { return }
        guard let reconciler else {
            // No writer (e.g. no calendar access): cannot materialize a mirror
            // event. Leave the proposal in place; the UI surfaces the access CTA.
            lastError = "Calendar write access is required to accept a block."
            return
        }
        do {
            _ = try await reconciler.accept(block)
        } catch {
            lastError = String(describing: error)
        }
        reloadBlocks()
    }

    public func acceptAll() async {
        for block in blocks where block.status == .proposed {
            await accept(blockID: block.id)
        }
    }

    public func reject(blockID: UUID) {
        guard let block = try? blockRepository.find(blockID) else { return }
        // Tear down the mirror event for an accepted block (it carries an
        // `externalEventID`) so rejecting it never orphans an event in the "Nexus"
        // calendar — mirrors `ScheduleRejectBlockTool`. Best-effort, like the agent
        // path; the soft-delete proceeds regardless.
        let eventID = block.externalEventID
        try? blockRepository.softDelete(block)
        reloadBlocks()
        if let eventID, let writer {
            _Concurrency.Task { @MainActor in try? await writer.deleteEvent(id: eventID) }
        }
    }

    /// Drag-to-adjust = implicit accept + estimate override (spec §7). Reschedules
    /// the block, then accepts it (materializing the mirror event).
    public func adjust(blockID: UUID, start: Date, end: Date) async {
        guard let block = try? blockRepository.find(blockID) else { return }
        try? blockRepository.reschedule(block, start: start, end: end)
        // A length change overrides the task estimate on the next reconcile read-back;
        // for a local drag we accept immediately so the mirror event reflects the tweak.
        if block.status == .proposed {
            await accept(blockID: blockID)
        } else {
            await syncAccepted(block: block)
        }
        reloadBlocks()
    }

    /// Add a manual block for a task, already `accepted` (spec §7). Materializes a
    /// mirror event when a writer is available.
    public func addManualBlock(taskID: UUID, title: String, start: Date, end: Date) async {
        guard
            let block = try? blockRepository.create(
                taskID: taskID,
                start: start,
                end: end,
                title: title,
                status: .proposed,
                origin: .manual
            )
        else { return }
        await accept(blockID: block.id)
        reloadBlocks()
    }

    private func syncAccepted(block: ScheduledBlock) async {
        guard let writer, let eventID = block.externalEventID else { return }
        do {
            let calendarID = try await writer.ensureNexusCalendar()
            try await writer.updateEvent(
                id: eventID,
                with: EventDraft(calendarID: calendarID, title: block.title, start: block.start, end: block.end)
            )
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Event CRUD (spec §9)

    @discardableResult
    public func createEvent(_ draft: EventDraft) async -> String? {
        guard let writer else { return nil }
        do {
            let id = try await writer.createEvent(draft)
            await load()
            return id
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    public func updateEvent(id: String, draft: EventDraft, span: CalendarEventSpan = .thisEvent) async {
        guard let writer else { return }
        do {
            try await writer.updateEvent(id: id, with: draft, span: span)
            await load()
        } catch {
            lastError = String(describing: error)
        }
    }

    public func deleteEvent(id: String, span: CalendarEventSpan = .thisEvent) async {
        guard let writer else { return }
        do {
            try await writer.deleteEvent(id: id, span: span)
            await load()
        } catch {
            lastError = String(describing: error)
        }
    }

    public func availableCalendars() async -> [CalendarInfo] {
        guard let listing else { return [] }
        return (try? await listing.availableCalendars()) ?? []
    }

    /// Build an editable `EventDraft` for a loaded external event (spec §9 edit
    /// path). Returns nil if the event is not in the current window or no write
    /// calendar is resolvable.
    public func draft(forEventID eventID: String, calendars: [CalendarInfo]) -> EventDraft? {
        guard let event = events.first(where: { $0.id == eventID }) else { return nil }
        let writeCalendar = preferences.writeCalendarID ?? calendars.first(where: \.isWritable)?.id ?? ""
        return EventDraft(
            calendarID: writeCalendar,
            title: event.title,
            start: event.start,
            end: event.end,
            location: event.location,
            attendees: event.attendees.compactMap(\.email)
        )
    }

    /// Open task ids + titles for the manual-block picker (candidates to schedule).
    public func schedulableTasks() -> [(id: UUID, title: String)] {
        let openRaw = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == openRaw },
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        return (try? context.fetch(descriptor))?.map { ($0.id, $0.title) } ?? []
    }

    public func savePreferences(_ prefs: CalendarPreferences) {
        preferencesStore.save(prefs)
    }

    // MARK: - Calendar math

    private func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
