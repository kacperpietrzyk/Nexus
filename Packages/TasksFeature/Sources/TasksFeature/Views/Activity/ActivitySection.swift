import NexusCore
import NexusUI
import SwiftUI

/// Read-only audit-log thread for an item (Tranche 2 Plan B, spec §4.1/§5).
/// Renders chrome-less inside an `inspectorCard` host — the `CommentsSection`
/// shape minus the composer: the log is append-only and views NEVER write it
/// (invariant I-B1). Reads the NEW NexusCore `ActivityEntry` entity only —
/// `ProjectExecutionModel.ActivityEntry` (the derived project feed DTO) is a
/// different type and stays untouched (invariant I-B2).
struct ActivitySection: View {
    let itemID: UUID
    let itemKind: ItemKind
    let repository: ActivityEntryRepository
    let projectName: (UUID) -> String?
    /// Bump to re-fetch after a mutation while the same item stays selected
    /// (the inspector passes `task.updatedAt`).
    let reloadToken: Date

    @State private var entries: [ActivityEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entries.isEmpty {
                Text("No activity yet")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            } else {
                ForEach(entries, id: \.id) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ActivityEntryFormatter.sentence(for: entry, projectName: projectName))
                            .font(NexusType.body)
                            .foregroundStyle(NexusColor.Text.primary)
                        Text("· \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }
                }
            }
        }
        // Reload when item identity changes (inspector reuses the view across
        // task-selection swaps — the CommentsSection idiom) and when the host
        // signals a mutation via `reloadToken`.
        .task(id: itemID) { reload() }
        .onChange(of: reloadToken) { _, _ in reload() }
    }

    private func reload() {
        entries = (try? repository.entries(for: itemID, kind: itemKind, limit: 50)) ?? []
    }
}
