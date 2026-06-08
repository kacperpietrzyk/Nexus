import Foundation
import NexusCore
import SwiftData

/// V10 -> V11 system-label seed (Projects tier, spec §7/§12). The V10 -> V11
/// *schema* delta is lightweight-additive (the `Label` table + the additive
/// `Project.statusRaw` / `TaskItem.workflowStateRaw` / `TaskItem.assignedAgent`
/// columns) and is handled by the split container's inference open in
/// `NexusModelContainer.make`; the system-label SEED runs here, as plain post-open
/// code, for the same reasons documented on `seedSystemLabelsIfNeeded`.
extension NexusModelContainer {
    /// `UserDefaults` key recording that the one-time V10 -> V11 system-label seed
    /// has run for a given store. Keyed by the store path so it is stable for the
    /// (fixed) production store and isolated per store in tests.
    static func systemLabelSeedCompletionKey(for storeURL: URL) -> String {
        "nexus.sync.systemLabelSeed.completed.\(storeURL.path)"
    }

    /// One-time post-open seed of the canonical system labels over the already-open
    /// production container (spec §7/§12).
    ///
    /// WHY post-open on the real container (and NOT a `.custom` migration stage) —
    /// identical to the V8 -> V9 body -> Note move (see
    /// `migrateTaskBodiesToNotesIfNeeded`): the production container is a split
    /// (synced + local-only) two-configuration container, and `makeContainer`
    /// deliberately DROPS `NexusMigrationPlan` on that path, relying on SwiftData
    /// lightweight *inference* for additive expansion. A `.custom didMigrate` would
    /// therefore NEVER fire for real users, and a single-config plan-driven pre-pass
    /// also fails because the production store carries composition extras (Meeting)
    /// never present in the plan's versioned schemas. So the V10 -> V11 delta stays
    /// lightweight-additive (handled by the split inference open), and the seed runs
    /// HERE, as plain code, on the container `make` already opened: inference has
    /// added the `Label` table, and `Label` is insertable through the synced
    /// configuration.
    ///
    /// Idempotent + marker-gated: once the seed has run for a store the marker
    /// short-circuits all later launches. `NexusMigrationPlan.seedSystemLabels` is
    /// itself idempotent (name-matched against existing rows), so even without the
    /// marker a re-run would not double-create.
    ///
    /// CROSS-DEVICE NOTE: `seedSystemLabels` mints a fresh `UUID()` per label and
    /// `Label` is a SYNCED partition. Two devices first-launching before CloudKit
    /// settles would each seed locally and, because CloudKit forbids
    /// `@Attribute(.unique)`, the rows cannot dedupe by record id — the same hazard
    /// documented for `ModelManifest`. Name-match idempotency only protects
    /// same-store re-runs. A deterministic per-`SystemLabel` UUID would fix this but
    /// is a NexusCore change to `SystemLabel`/`seedSystemLabels`, out of scope here.
    static func seedSystemLabelsIfNeeded(
        container: ModelContainer,
        storeURL: URL,
        defaults: UserDefaults = .standard
    ) throws {
        let completionKey = systemLabelSeedCompletionKey(for: storeURL)
        guard !defaults.bool(forKey: completionKey) else { return }

        let context = ModelContext(container)
        try NexusMigrationPlan.seedSystemLabels(in: context)

        // Seed complete (a store already carrying the full set is a harmless
        // no-op). Record completion so the labels are never re-scanned.
        defaults.set(true, forKey: completionKey)
    }
}
