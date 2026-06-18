import Foundation
import NexusCore
import NexusUI
import SwiftUI

// MARK: - Context menu dispatch
//
// Extracted from `LiquidWeekScreen.swift` to keep that file under the
// file/type-body length limits. These reach the screen's internal state
// (`viewModel`, `editorTarget`, `availableCalendars`, `undo`), so they live in
// a same-type extension rather than a free function.
extension LiquidWeekScreen {
    /// Routes a context menu action to the appropriate view-model call.
    func handleContextAction(item: TimelineItem, action: EventContextMenuAction) {
        switch action {
        case .openEditor, .openEditorForReschedule:
            guard item.kind == .event else { return }
            editorTarget = .edit(String(item.id.dropFirst("event-".count)))
        case .reschedulePlusOneDay: rescheduleEvent(item: item, offsetDays: 1)
        case .reschedulePlusOneWeek: rescheduleEvent(item: item, offsetDays: 7)
        case .convertToTask: convertItemToTask(item: item)
        case .copyAsMarkdown, .copyBlockAsMarkdown: copyItemAsMarkdown(item: item)
        case .deleteThisEvent: deleteEvent(item: item, span: .thisEvent)
        case .deleteFutureEvents: deleteEvent(item: item, span: .futureEvents)
        case .acceptBlock:
            guard let blockID = item.blockID else { return }
            _Concurrency.Task { @MainActor in await viewModel.accept(blockID: blockID) }
        case .rejectBlock: rejectBlock(item: item)
        }
    }

    private func rescheduleEvent(item: TimelineItem, offsetDays: Int) {
        guard item.kind == .event else { return }
        let eventID = String(item.id.dropFirst("event-".count))
        let cals = availableCalendars
        _Concurrency.Task { @MainActor in
            await viewModel.quickReschedule(eventID: eventID, offsetDays: offsetDays, calendars: cals)
        }
    }

    private func convertItemToTask(item: TimelineItem) {
        do {
            let taskID = try viewModel.convertEventToTask(item: item)
            undo.show(message: "Created task \"\(item.title)\"", icon: "checkmark.square") {
                viewModel.softDeleteCreatedTask(id: taskID)
            }
        } catch {
            viewModel.lastError = CalendarViewModel.errorMessage(error)
        }
    }

    private func copyItemAsMarkdown(item: TimelineItem) {
        let fmt = WeekEventBlock.timeFormatter
        let range = "\(fmt.string(from: item.start)) \u{2013} \(fmt.string(from: item.end))"
        PasteboardCopy.string(MarkdownExport.entity(title: item.title, metadata: [range]))
    }

    private func deleteEvent(item: TimelineItem, span: CalendarEventSpan) {
        guard item.kind == .event else { return }
        let eventID = String(item.id.dropFirst("event-".count))
        let title = item.title
        let icon = span == .thisEvent ? "trash" : "trash.slash"
        let message = span == .thisEvent ? "Deleted \"\(title)\"" : "Deleted future \"\(title)\" events"
        _Concurrency.Task { @MainActor in
            await viewModel.deleteEvent(id: eventID, span: span)
            undo.show(message: message, icon: icon) {
                viewModel.lastError = "Undo not available for calendar event deletion."
            }
        }
    }

    private func rejectBlock(item: TimelineItem) {
        guard let blockID = item.blockID else { return }
        viewModel.reject(blockID: blockID)
        undo.show(message: "Removed \"\(item.title)\"", icon: "minus.circle") {
            viewModel.lastError = "Undo not available for block removal."
        }
    }
}
