import NexusCore
import NexusUI
import SwiftUI
import TasksFeature
import UIKit

struct TodayTab: View {
    let onOpenTask: (TaskItem) -> Void
    let onOpenCapture: (CapturePane.Mode) -> Void
    let onOpenCommandPalette: () -> Void
    let onOpenAgent: () -> Void
    let onOpenPencilCapture: () -> Void
    var showsToolbarActions = true

    var body: some View {
        NavigationStack {
            TodayDashboard(
                showsNavigationRail: false,
                onOpenTask: onOpenTask,
                onOpenCapture: onOpenCapture,
                onOpenCommandPalette: onOpenCommandPalette,
                onOpenAgent: onOpenAgent
            )
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NexusColor.Background.base, for: .navigationBar)
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
