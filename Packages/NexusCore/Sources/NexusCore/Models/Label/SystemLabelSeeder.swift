import Foundation
import SwiftData

/// The single source of truth for seeding the canonical `SystemLabel` set (spec
/// §7). Both `LabelRepository.seedSystemLabels` (@MainActor, app runtime) and
/// `NexusMigrationPlan.seedSystemLabels` (non-isolated, V11 migration) delegate
/// here so the two paths can never drift (P4).
///
/// ## Identity, not name
/// A system label is considered already present only when a row with its stable
/// `SystemLabel.id` exists (live OR soft-deleted), or when a LIVE *system* label
/// shares its `(group, name)` (the legacy, pre-stable-id seed). A user's own
/// free/domain label that merely shares a name (e.g. a hand-made "bug") no longer
/// blocks the canonical system label — that was the P4 defect, which silently
/// broke `suggestedAgent` (bug → codex). Counting soft-deleted rows in the id
/// check stops a tombstoned system label from re-seeding as a duplicate.
public enum SystemLabelSeeder {
    public static func seed(in context: ModelContext, now: () -> Date = Date.init) throws {
        let all = try context.fetch(FetchDescriptor<Label>())
        // Every id ever minted (incl. tombstones) — guards against a duplicate row
        // for a soft-deleted system label.
        let idsPresent = Set(all.map(\.id))
        // Legacy / already-seeded system labels, matched by identity not bare name.
        let liveSystemKeys = Set(
            all
                .filter { $0.deletedAt == nil && $0.isSystem }
                .map { identityKey(group: $0.group, name: $0.name) }
        )

        let stamp = now()
        var didInsert = false
        for system in SystemLabel.allCases {
            if idsPresent.contains(system.id) { continue }
            if liveSystemKeys.contains(identityKey(group: system.group, name: system.name)) { continue }
            let label = Label(
                id: system.id,
                name: system.name,
                glyphKey: system.glyphKey,
                group: system.group,
                isSystem: true
            )
            label.createdAt = stamp
            label.updatedAt = stamp
            context.insert(label)
            didInsert = true
        }
        if didInsert {
            try context.save()
        }
    }

    /// Group-scoped, case-insensitive identity key. A unit separator keeps the
    /// group and name fields from colliding across boundaries.
    private static func identityKey(group: LabelGroup, name: String) -> String {
        "\(group.rawValue)\u{1F}\(name.lowercased())"
    }
}
