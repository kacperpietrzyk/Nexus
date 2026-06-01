import NexusUI
import SwiftUI

public struct MeetingsImportSettingsView: View {
    let composition: MeetingsComposition
    @State private var bundleURL: URL?

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Import")
            NexusSettingsCard {
                VStack(alignment: .leading, spacing: NexusSpacing.s3) {
                    #if os(macOS)
                    Button("Import from Circleback…") { pickFolder() }
                        .buttonStyle(.plain)
                        .foregroundStyle(NexusColor.Text.primary)
                        .font(NexusType.bodySmall.weight(.medium))
                    Text(
                        "Pick the folder produced by the Nexus Circleback MCP-dump "
                            + "(manifest.json + meetings/ + transcripts/ + action-items.json). "
                            + "Re-runs are safe — duplicates are skipped."
                    )
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                    #else
                    Text("Circleback import runs on Mac. Imported meetings will sync to this device via iCloud.")
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.muted)
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NexusSpacing.s4)
            }
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
