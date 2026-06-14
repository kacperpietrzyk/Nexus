import NexusUI
import SwiftUI

public struct MeetingsImportSettingsView: View {
    let composition: MeetingsComposition
    @State private var bundleURL: URL?

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        LiquidGlassCard("Import") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                #if os(macOS)
                NexusButton(variant: .default, size: .sm) {
                    pickFolder()
                } label: {
                    Text("Import from Circleback…")
                }
                Text(
                    "Pick the folder produced by the Nexus Circleback MCP-dump "
                        + "(manifest.json + meetings/ + transcripts/ + action-items.json). "
                        + "Re-runs are safe — duplicates are skipped."
                )
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                #else
                Text("Circleback import runs on Mac. Imported meetings will sync to this device via iCloud.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
