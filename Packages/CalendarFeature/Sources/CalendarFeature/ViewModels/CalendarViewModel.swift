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
    /// Non-error notice from the last `planDay` — e.g. an empty plan because it's
    /// past working hours (S8). Surfaced as a banner, distinct from `lastError`.
    public private(set) var planNotice: String?
    public private(set) var isLoading = false
    public var lastError: String?
    /// M1: accepted/manual blocks that now collide with calendar events.
    /// Runtime-only (computed by `BlockConflictDetector` after each store
    /// change; never persisted). The UI shows a conflicted treatment on these
    /// blocks plus a non-blocking "Replan" banner.
    public private(set) var conflictedBlockIDs: Set<UUID> = []

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
    private let autoReplanner: CalendarAutoReplanner
    private let changes: (any CalendarChangeObserving)?
    private let changeDebounce: Duration
    private var isHandlingExternalChange = false
    @ObservationIgnored nonisolated(unsafe) private var changeObserverToken: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var pendingChangeTask: _Concurrency.Task<Void, Never>?

    public init(
        context: ModelContext,
        reader: any CalendarEventProviding,
        writer: (any CalendarEventWriting)? = nil,
        listing: (any CalendarListing)? = nil,
        changes: (any CalendarChangeObserving)? = nil,
        changeDebounce: Duration = .milliseconds(800),
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
        self.changes = changes
        self.changeDebounce = changeDebounce
        self.autoReplanner = CalendarAutoReplanner(context: context, reconciler: reconciler)
        startObservingStoreChanges()
    }

    deinit {
        pendingChangeTask?.cancel()
        if let token = changeObserverToken {
            NotificationCenter.default.removeObserver(token)
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
            let fetched = try await reader.eventsBetween(start: win.start, end: win.end)
            // #6: hide events from calendars the user disabled in Settings. Empty
            // read-set ⇒ all granted (preferences semantic).
            events = preferences.visibleEvents(fetched)
        } catch {
            events = []
            lastError = Self.errorMessage(error)
        }
        reloadBlocks()
    }

    public func reloadBlocks() {
        let win = window
        blocks = (try? blockRepository.blocks(from: win.start, to: win.end)) ?? []
    }

    /// Unscheduled-task feed for the liquid Week strip + Scheduling Inspector.
    /// Owned HERE (not per-view `@State`): the two columns are sibling mounts
    /// sharing this view-model, so a schedule action from either side updates
    /// the one observable list. Internal — not part of the public surface.
    private(set) var unscheduledTasks: [WeekUnscheduledTask] = []

    /// Refreshes `unscheduledTasks`; the Week surfaces call this on mount and
    /// after every scheduling mutation.
    func reloadUnscheduledTasks() {
        unscheduledTasks = WeekUnscheduledLoader.load(modelContext: context)
    }

    /// Items laid out on the hour axis for a single `day`.
    public func timelineItems(forDay day: Date) -> [TimelineItem] {
        DayTimelineLayout.items(
            forDay: day,
            events: events,
            blocks: blocks,
            calendar: calendar,
            conflictedBlockIDs: conflictedBlockIDs
        )
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
            lastError = Self.errorMessage(error)
        }
        await load()
        return authorization
    }

    // MARK: - Plan my day (spec §10)

    /// Plan today (spec §10). The planner always plans the single current day; the
    /// previously-exposed `horizonDays` knob was never passed >1 and fetched only the
    /// day window, so a multi-day call would have overbooked future days (S2) — it is
    /// removed rather than left as a latent footgun.
    public func planDay() async {
        let win = window
        // #6: the planner must treat a disabled calendar's events as non-obstacles,
        // matching what the views display. Empty read-set ⇒ all granted.
        let fetched = preferences.visibleEvents(
            (try? await reader.eventsBetween(start: win.start, end: win.end)) ?? []
        )
        do {
            let result = try planner.planDay(
                events: fetched,
                prefs: preferences,
                now: now(),
                calendar: calendar
            )
            overload = result.overload
            // S8: planning after the working day has ended collapses today's window
            // to nothing → no proposals. Surface a clear notice instead of a silent
            // empty plan. (A daytime empty result just means nothing to schedule.)
            planNotice =
                result.proposals.isEmpty && isAfterWorkday(now())
                ? "It's past today's working hours — plan tomorrow instead."
                : nil
        } catch {
            lastError = Self.errorMessage(error)
        }
        reloadBlocks()
    }

    /// True when `instant` is at or after today's configured workday end — used to
    /// explain an empty plan produced late at night (S8).
    private func isAfterWorkday(_ instant: Date) -> Bool {
        guard
            let end = calendar.date(
                bySettingHour: preferences.workdayEnd.hour ?? 18,
                minute: preferences.workdayEnd.minute ?? 0,
                second: 0,
                of: instant
            )
        else { return false }
        return instant >= end
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
            lastError = Self.errorMessage(error)
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
            lastError = Self.errorMessage(error)
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
            lastError = Self.errorMessage(error)
            return nil
        }
    }

    public func updateEvent(id: String, draft: EventDraft, span: CalendarEventSpan = .thisEvent) async {
        guard let writer else { return }
        do {
            try await writer.updateEvent(id: id, with: draft, span: span)
            await load()
        } catch {
            lastError = Self.errorMessage(error)
        }
    }

    public func deleteEvent(id: String, span: CalendarEventSpan = .thisEvent) async {
        guard let writer else { return }
        do {
            try await writer.deleteEvent(id: id, span: span)
            await load()
        } catch {
            lastError = Self.errorMessage(error)
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
            // #4a: show every attendee as "Name (email)" / name / email rather than
            // dropping name-only attendees (those without a mailto). Display-only —
            // EventKit ignores attendees on write.
            attendees: event.attendees.compactMap(Self.attendeeDisplay)
        )
    }

    /// Format an attendee for the read-only editor list: "Name (email)" when both
    /// are present, otherwise whichever the invite carried; nil only when neither.
    static func attendeeDisplay(_ attendee: CalendarEvent.Attendee) -> String? {
        switch (attendee.name, attendee.email) {
        case (let name?, let email?): return "\(name) (\(email))"
        case (let name?, nil): return name
        case (nil, let email?): return email
        case (nil, nil): return nil
        }
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

    // MARK: - Error copy

    /// User-facing `lastError` copy: `CalendarProviderError` carries its own
    /// message (`LocalizedError`), so surfaces never render the enum's debug
    /// shape (`underlying("…")`); anything else falls back to the debug
    /// description as before.
    nonisolated static func errorMessage(_ error: any Error) -> String {
        if let providerError = error as? CalendarProviderError {
            return providerError.errorDescription ?? String(describing: error)
        }
        return String(describing: error)
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

// MARK: - Auto-replan on calendar change (M1)

extension CalendarViewModel {
    /// Register on the store-change seam. Bursty `EKEventStoreChanged`
    /// broadcasts (including ones our own mirror writes trigger) are debounced;
    /// our own writes then no-op through the pipeline (no conflicts → no churn).
    private func startObservingStoreChanges() {
        guard let changes else { return }
        changeObserverToken = changes.observeStoreChanges { [weak self] in
            _Concurrency.Task { @MainActor [weak self] in
                self?.scheduleExternalChangeHandling()
            }
        }
    }

    /// Trailing-edge debounce: each broadcast cancels the pending run.
    private func scheduleExternalChangeHandling() {
        pendingChangeTask?.cancel()
        let debounce = changeDebounce
        pendingChangeTask = _Concurrency.Task { @MainActor [weak self] in
            if debounce > .zero {
                try? await _Concurrency.Task.sleep(for: debounce)
            }
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.handleExternalChange()
        }
    }

    /// The M1 pipeline: reconcile external edits → conflict scan → regenerate
    /// broken auto proposals → publish the protected remainder. Public so tests
    /// (and pull-to-refresh-style surfaces) can drive it without the observer.
    public func handleExternalChange() async {
        guard hasCalendarAccess, !isHandlingExternalChange else { return }
        isHandlingExternalChange = true
        defer { isHandlingExternalChange = false }

        let instant = now()
        let dayStart = calendar.startOfDay(for: instant)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let fetched = preferences.visibleEvents(
            (try? await reader.eventsBetween(start: dayStart, end: dayEnd)) ?? []
        )
        do {
            let outcome = try await autoReplanner.handleStoreChange(
                events: fetched,
                prefs: preferences,
                now: instant,
                calendar: calendar
            )
            conflictedBlockIDs = Set(outcome.report.protectedBlockIDs)
            if outcome.replanned {
                overload = outcome.overload
            }
        } catch {
            lastError = Self.errorMessage(error)
        }
        await load()
    }

    /// The non-blocking "Replan" affordance (M1): tear down the conflicted
    /// accepted/manual blocks (mirror event + block — reject-path semantics)
    /// and re-propose their tasks into free slots as fresh `proposed` blocks.
    /// The user re-accepts — suggestive, not aggressive (spec §1).
    public func replanConflicted() async {
        let ids = conflictedBlockIDs.sorted { $0.uuidString < $1.uuidString }
        guard !ids.isEmpty else { return }

        var taskIDs: [UUID] = []
        for id in ids {
            guard let block = try? blockRepository.find(id) else { continue }
            taskIDs.append(block.taskID)
            if let eventID = block.externalEventID, let writer {
                try? await writer.deleteEvent(id: eventID)
            }
            try? blockRepository.softDelete(block)
        }

        let instant = now()
        let dayStart = calendar.startOfDay(for: instant)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let fetched = preferences.visibleEvents(
            (try? await reader.eventsBetween(start: dayStart, end: dayEnd)) ?? []
        )
        do {
            let result = try planner.replan(
                taskIDs: taskIDs,
                events: fetched,
                prefs: preferences,
                now: instant,
                calendar: calendar
            )
            planNotice =
                result.overload.unplacedTaskIDs.isEmpty
                ? nil
                : "Some replanned tasks didn't fit today — they're back in the task pool."
        } catch {
            lastError = Self.errorMessage(error)
        }
        conflictedBlockIDs = []
        reloadBlocks()
    }

    /// Dismiss the conflict banner without acting (the conflicts recompute on
    /// the next store change).
    public func dismissConflicts() {
        conflictedBlockIDs = []
    }

    /// Banner copy for the conflicted-blocks affordance (UI + tests share it).
    public nonisolated static func conflictNotice(count: Int) -> String {
        count == 1
            ? "1 scheduled block conflicts with a calendar event."
            : "\(count) scheduled blocks conflict with calendar events."
    }
}
