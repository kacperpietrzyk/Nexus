import InboxShell
import NexusUI
import SwiftUI
import TasksFeature

struct InboxTab: View {
    let onOpenItem: (InboxItem) -> Void
    let onOpenCapture: () -> Void
    let onOpenCommandPalette: () -> Void
    var showsToolbarActions = true

    var body: some View {
        NavigationStack {
            InboxView { item in onOpenItem(item) }
                .navigationTitle("Inbox")
                .toolbarBackground(.thinMaterial, for: .navigationBar)
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
