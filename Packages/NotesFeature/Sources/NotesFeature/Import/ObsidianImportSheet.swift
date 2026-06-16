import NexusCore
import NexusUI
import SwiftUI

/// Two-phase import sheet: scans the vault and shows a dry-run preview (create vs
/// skip counts) BEFORE any write, then the user confirms to execute. All state
/// lives in the shared `ObsidianImportModel`, so a Settings-host rebuild can't
/// dismiss the sheet or cancel the run — reopening re-binds to the same progress.
@MainActor
public struct ObsidianImportSheet: View {
    let repository: NoteRepository
    let vaultRoot: URL
    private let model = ObsidianImportModel.shared

    public init(repository: NoteRepository, vaultRoot: URL) {
        self.repository = repository
        self.vaultRoot = vaultRoot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Obsidian Vault").font(.headline)
            content
            actions
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 240)
        .task {
            if model.phase == .idle || model.phase == .failed {
                model.scan(vaultRoot: vaultRoot, repository: repository)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .scanning:
            HStack {
                ProgressView(); Text("Scanning vault…")
            }
        case .previewed:
            VStack(alignment: .leading, spacing: 6) {
                Text("To create: \(model.toCreate)")
                Text("To skip (already present): \(model.toSkip)")
                    .foregroundStyle(.secondary)
                if model.toSkip == 0 && model.toCreate > 0 {
                    Text(
                        "⚠︎ 0 skips — if you've imported before, the dedup key may be off. "
                            + "Check before importing."
                    )
                    .font(.caption)
                    .foregroundStyle(NexusColor.Status.danger)
                }
            }
        case .importing:
            VStack(alignment: .leading, spacing: 8) {
                Text("Importing \(model.toCreate) notes…")
                ProgressView(value: model.progress)
            }
        case .done:
            VStack(alignment: .leading, spacing: 6) {
                Text("Created: \(model.created)")
                Text("Skipped (already present): \(model.skipped)")
                    .foregroundStyle(.secondary)
                if model.failed > 0 {
                    Text("Failed: \(model.failed)").foregroundStyle(NexusColor.Status.danger)
                }
                errorDisclosure(model.errors)
            }
        case .failed:
            Text(model.errorText ?? "Import failed.")
                .foregroundStyle(NexusColor.Status.danger)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            Spacer()
            switch model.phase {
            case .previewed:
                Button("Cancel") { model.dismiss() }
                Button("Import \(model.toCreate) Notes") {
                    model.startImport(vaultRoot: vaultRoot, repository: repository)
                }
                .disabled(model.toCreate == 0)
            case .importing:
                Button("Close") {}.disabled(true)
            default:
                Button("Close") { model.dismiss() }
                    .disabled(model.phase == .idle || model.phase == .scanning)
            }
        }
    }

    @ViewBuilder
    private func errorDisclosure(_ errors: [String]) -> some View {
        if !errors.isEmpty {
            DisclosureGroup("\(errors.count) error(s)") {
                ScrollView {
                    ForEach(errors, id: \.self) { Text($0).font(.caption) }
                }
                .frame(maxHeight: 160)
            }
        }
    }
}
