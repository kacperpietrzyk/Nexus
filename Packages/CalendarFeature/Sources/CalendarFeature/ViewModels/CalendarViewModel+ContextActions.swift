import Foundation
import NexusCore
import SwiftData

// MARK: - Context menu actions (spec §Interaction rules)

extension CalendarViewModel {

    /// Quick-reschedule an external event by `offsetDays` days (e.g. +1 or +7)
    /// without opening the editor. Keeps the original duration, location and
    /// recurrence intact. No-ops gracefully when the writer is unavailable or
    /// the event is not found in the current window.
    public func quickReschedule(eventID: String, offsetDays: Int, calendars: [CalendarInfo]) async {
        guard let currentDraft = self.draft(forEventID: eventID, calendars: calendars) else {
            lastError = "Event not found — try navigating to its week first."
            return
        }
        guard let newStart = calendarInstance.date(byAdding: .day, value: offsetDays, to: currentDraft.start) else { return }
        guard let newEnd = calendarInstance.date(byAdding: .day, value: offsetDays, to: currentDraft.end) else { return }
        let updated = EventDraft(
            calendarID: currentDraft.calendarID,
            title: currentDraft.title,
            start: newStart,
            end: newEnd,
            isAllDay: currentDraft.isAllDay,
            location: currentDraft.location,
            attendees: currentDraft.attendees,
            recurrence: currentDraft.recurrence,
            alarmOffsets: currentDraft.alarmOffsets
        )
        await updateEvent(id: eventID, draft: updated, span: .thisEvent)
    }

    /// Convert a calendar event (or named block) into a Nexus `TaskItem`.
    /// Title, start date, and estimated duration are carried from the event; the
    /// event itself is NOT deleted (the user may keep it as a calendar commitment
    /// alongside the task). Returns the new task's id on success.
    ///
    /// Uses `TaskItemRepository` so the insertion goes through the same
    /// notifications + activity hooks as every other task-create path.
    @discardableResult
    public func convertEventToTask(item: TimelineItem) throws -> UUID {
        let duration = item.end.timeIntervalSince(item.start)
        let task = TaskItem(
            title: item.title,
            dueAt: item.start,
            estimatedDurationSeconds: duration > 0 ? Int(duration) : nil
        )
        let repo = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: currentDate
        )
        try repo.insert(task)
        return task.id
    }

    /// Soft-delete a task by id (undo path for `convertEventToTask`). Sets
    /// `deletedAt` on the live `@Model` reference and saves so CloudKit sync
    /// picks up the tombstone, matching every other soft-delete in the app.
    public func softDeleteCreatedTask(id: UUID) {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        guard let task = (try? modelContext.fetch(descriptor))?.first else { return }
        task.deletedAt = currentDate()
        try? modelContext.save()
    }
}
