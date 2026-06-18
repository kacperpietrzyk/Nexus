import Foundation

/// Actions surfaced on the event / block context menu (right-click / long-press).
/// The calling view translates these into view-model calls so `WeekEventBlock`
/// and `TimelineItemView` stay action-free (values only).
public enum EventContextMenuAction: Sendable {
    // MARK: - Event actions (item.kind == .event)
    /// Open the event in the full editor (same as a tap).
    case openEditor
    /// Reschedule +1 day without opening the editor.
    case reschedulePlusOneDay
    /// Reschedule +1 week without opening the editor.
    case reschedulePlusOneWeek
    /// Open the editor pre-loaded on the event (for manual reschedule).
    case openEditorForReschedule
    /// Convert the calendar event to a Nexus task (title + times carried over).
    case convertToTask
    /// Copy the event as Markdown (title, time range, location) to the pasteboard.
    case copyAsMarkdown
    /// Delete this occurrence of the event.
    case deleteThisEvent
    /// Delete this and all future occurrences.
    case deleteFutureEvents

    // MARK: - Block actions (item.kind == .proposedBlock / .acceptedBlock)
    /// Accept a proposed block.
    case acceptBlock
    /// Reject / soft-delete the block.
    case rejectBlock
    /// Copy the block as Markdown.
    case copyBlockAsMarkdown
}
