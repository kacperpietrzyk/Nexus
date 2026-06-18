import NexusCore
import NexusUI
import SwiftUI

/// Lightweight sheet listing active projects. Used by the bulk "Move" action
/// and the per-row "Move to Project…" context menu item.
struct ProjectPickerSheet: View {
    let projects: [Project]
    let title: String
    let onSelect: (UUID?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // "Inbox" (no project) is always offered first.
                Button {
                    onSelect(nil)
                } label: {
                    Label("Inbox (no project)", systemImage: "tray")
                        .foregroundStyle(DS.ColorToken.textPrimary)
                }
                .listRowBackground(Color.clear)

                ForEach(projects) { project in
                    Button {
                        onSelect(project.id)
                    } label: {
                        Label(project.name, systemImage: "folder")
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 320)
        #endif
    }
}
