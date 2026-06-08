import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Deterministic fake `CalendarEventWriting` (spec §17). Records every write and
/// its target calendar so tests can assert foreign calendars are never touched,
/// and stubs the scoped read so read-back diffing is exercised without EventKit.
private final class FakeCalendarWriter: CalendarEventWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var nexusCalendarID: String
    private var nextEventSeq = 0
    private(set) var events: [String: CalendarEventSnapshot] = [:]

    // Recorded calls.
    private(set) var createdCalendarIDs: [String] = []
    private(set) var updatedCalendarIDs: [String] = []
    private(set) var updatedSpans: [CalendarEventSpan] = []
    private(set) var deletedEventIDs: [String] = []
    private(set) var deletedSpans: [CalendarEventSpan] = []
    private(set) var ensureNexusCount = 0

    init(nexusCalendarID: String = "nexus-cal") {
        self.nexusCalendarID = nexusCalendarID
    }

    func requestFullAccess() async throws -> CalendarAuthorizationStatus { .fullAccess }

    func ensureNexusCalendar() async throws -> String {
        locked {
            ensureNexusCount += 1
            return nexusCalendarID
        }
    }

    func createEvent(_ draft: EventDraft) async throws -> String {
        locked {
            nextEventSeq += 1
            let id = "evt-\(nextEventSeq)"
            createdCalendarIDs.append(draft.calendarID)
            events[id] = CalendarEventSnapshot(
                eventID: id,
                calendarID: draft.calendarID,
                title: draft.title,
                start: draft.start,
                end: draft.end
            )
            return id
        }
    }

    func updateEvent(id: String, with draft: EventDraft, span: CalendarEventSpan) async throws {
        locked {
            updatedCalendarIDs.append(draft.calendarID)
            updatedSpans.append(span)
            events[id] = CalendarEventSnapshot(
                eventID: id,
                calendarID: draft.calendarID,
                title: draft.title,
                start: draft.start,
                end: draft.end
            )
        }
    }

    func deleteEvent(id: String, span: CalendarEventSpan) async throws {
        locked {
            deletedEventIDs.append(id)
            deletedSpans.append(span)
            events[id] = nil
        }
    }

    func events(inCalendar calendarID: String, start: Date, end: Date) async throws -> [CalendarEventSnapshot] {
        locked {
            events.values
                .filter { $0.calendarID == calendarID && $0.start < end && $0.end > start }
                .sorted { $0.eventID < $1.eventID }
        }
    }

    /// Global by-identifier lookup, ignoring calendar + window (mirrors EventKit's
    /// `event(withIdentifier:)`). Returns nil only when the event is truly gone.
    func eventSnapshot(id: String) async throws -> CalendarEventSnapshot? {
        locked { events[id] }
    }

    // Test helpers to mutate the "store" out-of-band (simulating Apple Calendar edits).
    func mutateEvent(id: String, start: Date, end: Date) {
        locked {
            guard let existing = events[id] else { return }
            events[id] = CalendarEventSnapshot(
                eventID: id,
                calendarID: existing.calendarID,
                title: existing.title,
                start: start,
                end: end
            )
        }
    }

    func removeEventFromStore(id: String) {
        locked { events[id] = nil }
    }

    /// Simulate the user dragging the mirror event onto another calendar: it leaves
    /// the window-scoped Nexus fetch but survives globally under the same id (R1).
    func moveEventToCalendar(id: String, calendarID: String) {
        locked {
            guard let existing = events[id] else { return }
            events[id] = CalendarEventSnapshot(
                eventID: id,
                calendarID: calendarID,
                title: existing.title,
                start: existing.start,
                end: existing.end
            )
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@Suite("CalendarSyncReconciler")
@MainActor
struct CalendarSyncReconcilerTests {
    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ScheduledBlock.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - accept → event create

    @Test("accept creates a mirror event in the Nexus calendar and flips the block to accepted")
    func acceptCreatesEvent() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let block = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800), title: "Write report")
        let eventID = try await reconciler.accept(block)

        #expect(block.status == .accepted)
        #expect(block.externalEventID == eventID)
        #expect(writer.createdCalendarIDs == ["nexus-cal"])
        // Invariant §14: accepted ⇒ externalEventID != nil.
        #expect(block.externalEventID != nil)
    }

    @Test("accept is idempotent — re-accepting reuses the mirror event, no second event")
    func acceptIdempotent() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let block = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800))
        let first = try await reconciler.accept(block)
        let second = try await reconciler.accept(block)

        #expect(first == second)
        #expect(writer.createdCalendarIDs.count == 1)
    }

    // MARK: - observer → block update (move vs resize)

    @Test("reconcile applies an external move to the block without touching the task estimate")
    func reconcileMoveUpdatesBlockOnly() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let task = TaskItem(title: "Move me")
        context.insert(task)
        try context.save()
        let block = try repo.create(taskID: task.id, start: t0, end: t0.addingTimeInterval(1800), title: "Move me")
        let eventID = try await reconciler.accept(block)

        // Same length (1800s), shifted +1h.
        writer.mutateEvent(id: eventID, start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400))
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        #expect(block.start == t0.addingTimeInterval(3600))
        #expect(block.end == t0.addingTimeInterval(5400))
        // Pure move ⇒ estimate untouched (spec §8).
        #expect(task.estimatedDurationSeconds == nil)
        #expect(task.durationSource == nil)
    }

    @Test("reconcile applies an external resize and overrides the task estimate (explicit)")
    func reconcileResizeOverridesEstimate() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let task = TaskItem(title: "Resize me")
        context.insert(task)
        try context.save()
        let block = try repo.create(taskID: task.id, start: t0, end: t0.addingTimeInterval(1800), title: "Resize me")
        let eventID = try await reconciler.accept(block)

        // Stretched from 1800s to 3600s.
        writer.mutateEvent(id: eventID, start: t0, end: t0.addingTimeInterval(3600))
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        #expect(block.end == t0.addingTimeInterval(3600))
        #expect(task.estimatedDurationSeconds == 3600)
        #expect(task.durationSource == .explicit)
    }

    // MARK: - conflict (last-writer-wins)

    @Test("external edit wins — read-back overwrites local block state (last-writer-wins)")
    func externalEditWins() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let block = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800))
        let eventID = try await reconciler.accept(block)

        // Local edit then a competing external edit; external wins on read-back.
        try repo.reschedule(block, start: t0.addingTimeInterval(600), end: t0.addingTimeInterval(2400))
        writer.mutateEvent(id: eventID, start: t0.addingTimeInterval(7200), end: t0.addingTimeInterval(9000))
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        #expect(block.start == t0.addingTimeInterval(7200))
        #expect(block.end == t0.addingTimeInterval(9000))
    }

    // MARK: - deleted in Apple Calendar

    @Test("event deleted in Apple Calendar soft-deletes the block (task returns to pool)")
    func externalDeleteRemovesBlock() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let taskID = UUID()
        let block = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800))
        let eventID = try await reconciler.accept(block)

        writer.removeEventFromStore(id: eventID)
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        #expect(try repo.find(block.id) == nil)
        #expect(try repo.blocks(for: taskID).isEmpty)
    }

    @Test("event moved to another calendar is NOT treated as deleted (R1)")
    func movedToAnotherCalendarBlockSurvives() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let taskID = UUID()
        let block = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800))
        let eventID = try await reconciler.accept(block)

        // User drags the accepted mirror event onto the Work calendar: it leaves the
        // window-scoped Nexus fetch but survives globally under the same identifier.
        writer.moveEventToCalendar(id: eventID, calendarID: "work")
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        // The block is NOT soft-deleted (the task does not return to the pool).
        #expect(try repo.find(block.id) != nil)
        #expect(try repo.blocks(for: taskID).count == 1)
        #expect(block.status == .accepted)
    }

    @Test("a block outside the refetch window is NOT treated as deleted")
    func outOfWindowBlockSurvives() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        // Block one week out; its event exists but falls outside the reconcile window.
        let farStart = t0.addingTimeInterval(7 * 86_400)
        let block = try repo.create(taskID: UUID(), start: farStart, end: farStart.addingTimeInterval(1800))
        _ = try await reconciler.accept(block)

        // Reconcile only today's window.
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        #expect(try repo.find(block.id) != nil)
    }

    // MARK: - task delete → event delete

    @Test("task removed deletes the mirror event and soft-deletes all its blocks")
    func taskRemovedDeletesEventAndBlocks() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter()
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let taskID = UUID()
        let accepted = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800))
        let proposed = try repo.create(taskID: taskID, start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400))
        let eventID = try await reconciler.accept(accepted)

        try await reconciler.handleTaskRemoved(taskID: taskID)

        #expect(writer.deletedEventIDs == [eventID])
        // Mirror events are always single occurrences → the scheduler deletes with
        // the default `.thisEvent` span, never `.futureEvents` (R2/R3 default path).
        #expect(writer.deletedSpans == [.thisEvent])
        #expect(try repo.find(accepted.id) == nil)
        #expect(try repo.find(proposed.id) == nil)
    }

    // MARK: - foreign calendars untouched

    @Test("the reconciler only ever writes the Nexus calendar")
    func foreignCalendarsUntouched() async throws {
        let context = try makeContext()
        let writer = FakeCalendarWriter(nexusCalendarID: "nexus-cal")
        let repo = ScheduledBlockRepository(context: context)
        let reconciler = CalendarSyncReconciler(context: context, writer: writer, blocks: repo)

        let block = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800))
        let eventID = try await reconciler.accept(block)
        writer.mutateEvent(id: eventID, start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400))
        try await reconciler.reconcile(window: t0, to: t0.addingTimeInterval(86_400))

        let allWrites = writer.createdCalendarIDs + writer.updatedCalendarIDs
        #expect(allWrites.allSatisfy { $0 == "nexus-cal" })
    }
}
