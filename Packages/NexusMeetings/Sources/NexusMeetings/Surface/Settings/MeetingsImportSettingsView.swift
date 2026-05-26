import SwiftUI

public struct MeetingsImportSettingsView: View {
    let composition: MeetingsComposition
    @State private var bundleURL: URL?

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        Section("Import") {
            #if os(macOS)
            Button("Import from Circleback…") { pickFolder() }
            Text(
                "Pick the folder produced by the Nexus Circleback MCP-dump "
                    + "(manifest.json + meetings/ + transcripts/ + action-items.json). "
                    + "Re-runs are safe — duplicates are skipped."
            )
            .font(.caption).foregroundStyle(.secondary)
            #else
            Text("Circleback import runs on Mac. Imported meetings will sync to this device via iCloud.")
                .foregroundStyle(.secondary)
            #endif
        }
        .sheet(
            item: Binding(
                get: { bundleURL.map { ImportRoot(url: $0) } },
                set: { bundleURL = $0?.url }
            )
        ) { root in
            CirclebackImportSheet(composition: composition, bundleURL: root.url)
        }
    }

    #if os(macOS)
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            bundleURL = url
        }
    }
    #endif

    private struct ImportRoot: Identifiable {
        let url: URL
        var id: String { url.path }
    }
}
