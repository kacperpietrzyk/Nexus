import NexusCore
import NexusUI
import SwiftUI

/// Attaches a context menu (right-click / long-press) to any calendar event or
/// block view. Actions are forwarded to the caller via `onAction`; the modifier
/// is inert when `onAction` is nil (reference snapshots, series-preview ghosts).
///
/// Menu structure:
///   - External event (.event): Open/Edit · Reschedule submenu · Convert to Task
///     · Copy as Markdown · ─── · Delete This Event · Delete Future Events
///   - Proposed block:          Accept · Reject · Copy as Markdown
///   - Accepted block:          Reject / Remove · Copy as Markdown
///   - Series preview ghost:    (no menu — non-interactive, per RecurringSeriesProjector)
struct EventContextMenuModifier: ViewModifier {
    let item: TimelineItem
    /// Nil suppresses the menu entirely (reference-mode, series-preview ghosts).
    let onAction: ((EventContextMenuAction) -> Void)?

    func body(content: Content) -> some View {
        if let onAction, item.kind != .seriesPreview {
            content.contextMenu {
                switch item.kind {
                case .event:
                    eventMenuItems(onAction: onAction)
                case .proposedBlock:
                    proposedBlockMenuItems(onAction: onAction)
                case .acceptedBlock:
                    acceptedBlockMenuItems(onAction: onAction)
                case .seriesPreview:
                    EmptyView()
                }
            }
        } else {
            content
        }
    }

    // MARK: - External event menu

    @ViewBuilder
    private func eventMenuItems(onAction: @escaping (EventContextMenuAction) -> Void) -> some View {
        Button {
            onAction(.openEditor)
        } label: {
            Label("Open / Edit", systemImage: "pencil")
        }

        Menu {
            Button {
                onAction(.reschedulePlusOneDay)
            } label: {
                Label("+1 Day", systemImage: "calendar.badge.plus")
            }
            Button {
                onAction(.reschedulePlusOneWeek)
            } label: {
                Label("+1 Week", systemImage: "calendar.badge.plus")
            }
            Divider()
            Button {
                onAction(.openEditorForReschedule)
            } label: {
                Label("Choose Date…", systemImage: "calendar")
            }
        } label: {
            Label("Reschedule", systemImage: "arrow.right.circle")
        }

        Button {
            onAction(.convertToTask)
        } label: {
            Label("Convert to Task", systemImage: "checkmark.square")
        }

        Button {
            onAction(.copyAsMarkdown)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            onAction(.deleteThisEvent)
        } label: {
            Label("Delete This Event", systemImage: "trash")
        }

        Button(role: .destructive) {
            onAction(.deleteFutureEvents)
        } label: {
            Label("Delete Future Events", systemImage: "trash.slash")
        }
    }

    // MARK: - Proposed block menu

    @ViewBuilder
    private func proposedBlockMenuItems(onAction: @escaping (EventContextMenuAction) -> Void) -> some View {
        Button {
            onAction(.acceptBlock)
        } label: {
            Label("Accept Block", systemImage: "checkmark.circle")
        }

        Button {
            onAction(.copyBlockAsMarkdown)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            onAction(.rejectBlock)
        } label: {
            Label("Reject Block", systemImage: "xmark.circle")
        }
    }

    // MARK: - Accepted block menu

    @ViewBuilder
    private func acceptedBlockMenuItems(onAction: @escaping (EventContextMenuAction) -> Void) -> some View {
        Button {
            onAction(.copyBlockAsMarkdown)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            onAction(.rejectBlock)
        } label: {
            Label("Remove Block", systemImage: "minus.circle")
        }
    }
}
