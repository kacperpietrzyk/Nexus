import InboxShell
import NexusUI
import SwiftUI
import TasksFeature

struct InboxTab: View {
    let onOpenItem: (FeedItem) -> Void
    let onOpenCapture: () -> Void
    let onOpenCommandPalette: () -> Void
    var onUnreadCountChanged: @MainActor (Int) -> Void = { _ in }
    var markSeen: @MainActor (FeedItem) async -> Void = { _ in }
    var dismissItem: @MainActor (FeedItem) async -> Void = { _ in }
    var snoozeItem: @MainActor (FeedItem, Date) async -> Void = { _, _ in }
    var showsToolbarActions = true

    var body: some View {
        NavigationStack {
            InboxView(
                onUnreadCountChanged: onUnreadCountChanged,
                onOpen: { item in onOpenItem(item) },
                markSeen: markSeen,
                dismiss: dismissItem,
                snooze: snoozeItem
            )
            .navigationTitle("Inbox")
            .toolbarBackground(NexusColor.Background.base, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbar {
                if showsToolbarActions {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onOpenCommandPalette) {
                            Image(systemName: "command")
                        }
                        .accessibilityLabel("Open command palette")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenCapture) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Capture task")
                    }
                }
            }
        }
    }
}
