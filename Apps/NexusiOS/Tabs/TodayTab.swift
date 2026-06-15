import NexusCore
import NexusUI
import SwiftUI
import TasksFeature
import UIKit

struct TodayTab<Content: View>: View {
    let onOpenCapture: (CapturePane.Mode) -> Void
    let onOpenCommandPalette: () -> Void
    let onOpenPencilCapture: () -> Void
    var showsToolbarActions = true
    /// The Today content — the ported `LiquidTodayScreen`, composed by the host
    /// (`ContentView`) where the cross-module seams live. `TodayTab` only owns
    /// the iOS navigation chrome (title + translucent nav bar + toolbar actions).
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Today")
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

                    ToolbarItem(placement: .topBarLeading) {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            Button(action: onOpenPencilCapture) {
                                Image(systemName: "pencil.tip")
                            }
                            .accessibilityLabel("Pencil capture")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if UIDevice.current.userInterfaceIdiom == .pad {
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
}
