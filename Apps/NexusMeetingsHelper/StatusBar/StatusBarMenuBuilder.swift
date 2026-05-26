import AppKit
import SwiftUI

enum StatusBarMenuBuilder {
    @MainActor
    static func makeRoot() -> some View {
        StatusBarRootView()
    }
}

private struct StatusBarRootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nexus Meetings")
                .font(.headline)
            Text("Use the menu bar dot to follow a recording in progress.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Button("Open Nexus", action: openNexus)
            Button("Quit Meetings Helper") {
                NSApp.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }

    private func openNexus() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Nexus.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
