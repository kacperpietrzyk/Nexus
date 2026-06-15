import NexusCore
import NexusUI
import SwiftUI
import TasksFeature
import UIKit

struct ProjectsTab<Content: View>: View {
    let onOpenCapture: (CapturePane.Mode) -> Void
    let onOpenCommandPalette: () -> Void
    var showsToolbarActions = true
    /// The Projects content — the shared `LiquidProjectScreen`, composed by the
    /// host (`ContentView`) where `liquidProjectsModel` / the open-task seam live.
    /// `ProjectsTab` only owns the iOS navigation chrome (title + translucent nav
    /// bar + toolbar actions), mirroring `TodayTab`.
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Projects")
                .navigationBarTitleDisplayMode(.inline)
                // Translucent native nav bar so the aurora canvas reads to the top
                // edge (the iOS half of the Liquid identity) instead of an opaque band.
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .preferredColorScheme(.dark)
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
                            Button {
                                onOpenCapture(.task)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Capture task")
                        }
                    }
                }
        }
    }
}
