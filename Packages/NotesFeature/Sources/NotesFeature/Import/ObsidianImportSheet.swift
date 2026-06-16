import NexusCore
import NexusUI
import SwiftUI

/// Two-phase import sheet: first scans the vault and shows a dry-run preview
/// (how many notes will be created vs skipped) so a key mismatch surfaces BEFORE
/// any write; the user then confirms to execute.
@MainActor
public struct ObsidianImportSheet: View {
    let repository: NoteRepository
    let vaultRoot: URL
    @State private var plan: ObsidianImportPlan?
    @State private var planning = true
    @State private var running = false
    @State private var result: ObsidianImportResult?
    @State private var errorText: String?
    @State private var progress: Double = 0
    @Environment(\.dismiss) private var dismiss

    public init(repository: NoteRepository, vaultRoot: URL) {
        self.repository = repository
        self.vaultRoot = vaultRoot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Obsidian Vault").font(.headline)

            if planning {
                HStack { ProgressView(); Text("Scanning vault…") }
            } else if let result {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Created: \(result.created)")
                    Text("Skipped (already present): \(result.skipped)")
                        .foregroundStyle(.secondary)
                    if result.failed > 0 {
                        Text("Failed: \(result.failed)").foregroundStyle(NexusColor.Status.danger)
                    }
                    errorDisclosure(result.errors)
                }
            } else if let plan {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To create: \(plan.toCreate.count)")
                    Text("To skip (already present): \(plan.toSkip.count)")
                        .foregroundStyle(.secondary)
                    if plan.toSkip.isEmpty && !plan.toCreate.isEmpty {
                        Text("⚠︎ 0 skips — if you've imported before, the dedup key may be off. "
                            + "Check before importing.")
                            .font(.caption)
                            .foregroundStyle(NexusColor.Status.danger)
                    }
                }
                if running { ProgressView(value: progress) }
            } else if let errorText {
                Text(errorText).foregroundStyle(NexusColor.Status.danger)
            }

            HStack {
                Spacer()
                if result == nil, !planning, let plan, errorText == nil {
                    Button("Cancel") { dismiss() }.disabled(running)
                    Button("Import \(plan.toCreate.count) Notes") {
                        Task { await runImport(plan) }
                    }
                    .disabled(running || plan.toCreate.isEmpty)
                } else {
                    Button("Close") { dismiss() }.disabled(planning || running)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 240)
        .task { await buildPlan() }
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

    private func buildPlan() async {
        planning = true
        defer { planning = false }
        do {
            let discovered = try ObsidianVaultImporter.discover(vaultRoot: vaultRoot)
            let existing = try ObsidianVaultImporter.existingKeys(in: repository)
            plan = ObsidianVaultImporter().plan(discovered: discovered, existing: existing)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runImport(_ plan: ObsidianImportPlan) async {
        running = true
        defer { running = false }
        do {
            let outcome = try await ObsidianVaultImporter().execute(
                plan: plan,
                repo: repository,
                vaultRoot: vaultRoot,
                progress: { value in progress = value }
            )
            result = outcome
            progress = 1
        } catch {
            errorText = error.localizedDescription
        }
    }
}
