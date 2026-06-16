import NexusCore
import NexusUI
import SwiftUI

/// Settings card that launches the Obsidian vault import (macOS). Presentation is
/// driven by the shared `ObsidianImportModel` (not transient view `@State`) so a
/// store-change rebuild of the Settings host can't dismiss the sheet mid-import.
public struct ObsidianImportSettingsView: View {
    let repository: NoteRepository
    private let model = ObsidianImportModel.shared

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
                get: { model.activeVault },
                set: { if $0 == nil { model.dismiss() } }
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
            model.present(vaultRoot: url)
        }
    }
    #endif
}
