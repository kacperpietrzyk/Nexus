import NexusCore
import NexusUI
import SwiftUI

/// Settings card that launches the Obsidian vault import (macOS). Self-contained,
/// mirrors `MeetingsImportSettingsView`: a folder picker feeds the two-phase
/// `ObsidianImportSheet`.
public struct ObsidianImportSettingsView: View {
    let repository: NoteRepository
    @State private var vaultURL: URL?

    public init(repository: NoteRepository) {
        self.repository = repository
    }

    public var body: some View {
        LiquidGlassCard("Import from Obsidian") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                #if os(macOS)
                NexusButton(variant: .default, size: .sm) {
                    pickFolder()
                } label: {
                    Text("Import Obsidian Vault…")
                }
                Text(
                    "Pick your Obsidian vault folder. Every .md file imports as a note "
                        + "with its folder path preserved (frontmatter dropped). Read straight "
                        + "from disk — no network. Re-runs are safe: notes already present "
                        + "(same title + folder) are skipped."
                )
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                #else
                Text("Obsidian import runs on Mac. Imported notes sync to this device via iCloud.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(
            item: Binding(
                get: { vaultURL.map { VaultRoot(url: $0) } },
                set: { vaultURL = $0?.url }
            )
        ) { root in
            ObsidianImportSheet(repository: repository, vaultRoot: root.url)
        }
    }

    #if os(macOS)
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            vaultURL = url
        }
    }
    #endif

    private struct VaultRoot: Identifiable {
        let url: URL
        var id: String { url.path }
    }
}
