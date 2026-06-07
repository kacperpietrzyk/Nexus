import Foundation
import NexusCore
import SwiftData

/// V8 -> V9 Notes content-layer data move (spec §15; the crown-jewel data-safety
/// step). The V8 -> V9 *schema* delta is lightweight-additive and is handled by
/// the split container's inference open in `NexusModelContainer.make`; the
/// `TaskItem.body` -> `Note` conversion runs here, as plain post-open code, for
/// the reasons documented on `migrateTaskBodiesToNotesIfNeeded`.
extension NexusModelContainer {
    /// `UserDefaults` key recording that the one-time V8 -> V9 `TaskItem.body` ->
    /// `Note` conversion has run for a given store. Keyed by the store path so it
    /// is stable for the (fixed) production store and isolated per store in tests.
    static func taskBodyToNoteMigrationCompletionKey(for storeURL: URL) -> String {
        "nexus.sync.taskBodyToNoteMigration.completed.\(storeURL.path)"
    }

    /// One-time post-open conversion that runs the V8 -> V9 `TaskItem.body` ->
    /// `Note` data move over the already-open production container (spec §15).
    ///
    /// WHY post-open on the real container (and NOT a `.custom` migration stage):
    /// the production container is a split (synced + local-only) two-configuration
    /// container, and `makeContainer` deliberately DROPS `NexusMigrationPlan` on
    /// that path, relying on SwiftData lightweight *inference* for additive
    /// expansion (see `splitContainerInfersV6ToV7LightweightExpansionOnDisk`). Two
    /// hard constraints rule out a staged custom stage here:
    ///   1. Inference can add the additive `Note` table and the two `UUID?` ref
    ///      fields, but can NEVER run a `.custom didMigrate` data move — so a
    ///      custom stage would silently never run for real users.
    ///   2. Even a single-config plan-driven pre-pass fails: plan-based staged
    ///      migration matches the on-disk store's version hashes against the plan's
    ///      versioned schemas, but the production store carries composition extras
    ///      (Meeting) that are NEVER in those schemas (package cycle) — SwiftData
    ///      throws "unknown coordinator model version".
    /// So the V8 -> V9 delta stays lightweight-additive (handled by the split
    /// inference open), and the body -> Note move runs HERE, as plain code, on the
    /// container `make` already opened: inference has added the `Note` table and
    /// the ref columns, the retained legacy `body` column is still readable, and
    /// `Note` is insertable through the synced configuration.
    ///
    /// Idempotent + marker-gated: once the conversion has run for a store the
    /// marker short-circuits all later launches. `migrateTaskBodiesToNotes` is
    /// itself idempotent (skips tasks already carrying a `noteRef`), so even
    /// without the marker a re-run would not double-create.
    static func migrateTaskBodiesToNotesIfNeeded(
        container: ModelContainer,
        storeURL: URL,
        defaults: UserDefaults = .standard
    ) throws {
        let completionKey = taskBodyToNoteMigrationCompletionKey(for: storeURL)
        guard !defaults.bool(forKey: completionKey) else { return }

        let context = ModelContext(container)
        try NexusMigrationPlan.migrateTaskBodiesToNotes(in: context)

        // Conversion complete (a fresh install with zero tasks is a harmless
        // no-op). Record completion so the container's tasks are never re-scanned.
        defaults.set(true, forKey: completionKey)
    }
}
