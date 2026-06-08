import Foundation
import NexusCore
import SwiftData

/// V11 -> V12 People backfill wiring (spec §8 / M1). The V11 -> V12 *schema* delta
/// is lightweight-additive (the `Person` table) and is handled by the split
/// container's inference open in `NexusModelContainer.make`; the
/// `participantsJSON` -> `Person` data move runs HERE, as marker-gated post-open
/// code, for the same reasons documented on `seedSystemLabelsIfNeeded`.
///
/// Unlike its siblings, this one CANNOT be called from `make()`: the backfill is
/// generic over the concrete `Meeting` model (a composition-time extra NexusSync
/// can't import), so the INVOCATION is deferred to first-launch bootstrap where
/// `Meeting.self` is nameable. The full apps (iOS/Mac) call
/// `MeetingsComposition.backfillPeopleIfNeeded(container:)` right after `make()`;
/// extensions (Share / Digest / Widgets / Watch / Helper) do NOT — the one host
/// app run per launch is enough and the work is idempotent regardless.
extension NexusModelContainer {
    /// `UserDefaults` key recording that the one-time V11 -> V12 People backfill has
    /// run for a given store. Keyed by the store path so it is stable for the
    /// (fixed) production store and isolated per store in tests.
    static func peopleBackfillCompletionKey(for storeURL: URL) -> String {
        "nexus.sync.peopleBackfill.completed.\(storeURL.path)"
    }

    /// One-time post-open `participantsJSON` -> `Person` backfill over the
    /// already-open V12 container (spec §8). Generic over the concrete `Meeting`
    /// type — the composition root supplies `Meeting.self` + the two key paths.
    ///
    /// Idempotent + marker-gated: once the backfill has run over a non-empty
    /// meeting set the marker short-circuits later launches.
    /// `backfillPeopleFromMeetingParticipants` is itself idempotent (global name
    /// dedup + edge dedup), so even without the marker a re-run never
    /// double-creates. On throw the marker is left UNSET so the backfill retries
    /// on the next launch.
    ///
    /// CRITICAL — do NOT mark on a zero-meeting run. On a fresh-install upgrade
    /// CloudKit may not have synced the user's historical meetings down by first
    /// launch; marking an empty store "done" would permanently skip the backfill
    /// and ship People empty of past attendees — the exact M1 failure. Leaving it
    /// unmarked retries once meetings arrive, at negligible cost (an empty fetch).
    /// This mirrors `backfillLegacyConflictLogsIfNeeded`'s leave-unmarked-on-empty
    /// convention. (New meetings get their `Person` links at processing time via
    /// `MeetingPeopleLinker`; this backfill only catches historical ones.)
    public static func backfillPeopleFromMeetingsIfNeeded<M: PersistentModel>(
        meetingType: M.Type,
        participantsKeyPath: KeyPath<M, Data?>,
        idKeyPath: KeyPath<M, UUID>,
        container: ModelContainer,
        defaults: UserDefaults = .standard
    ) throws {
        let completionKey = peopleBackfillCompletionKey(for: syncedStoreURL(of: container))
        guard !defaults.bool(forKey: completionKey) else { return }

        let context = ModelContext(container)
        let processedMeetings = try NexusMigrationPlan.backfillPeopleFromMeetingParticipants(
            meetingType: meetingType,
            participantsKeyPath: participantsKeyPath,
            idKeyPath: idKeyPath,
            in: context
        )

        // Record completion only after a run over a non-empty meeting set, so a
        // later launch retries once CloudKit has synced historical meetings down.
        if processedMeetings {
            defaults.set(true, forKey: completionKey)
        }
    }

    /// The synced (main) configuration's store URL — what the marker is keyed on,
    /// matching the URL `make()` passes to the sibling post-open helpers. Falls
    /// back to any configuration (in-memory test containers carry only an unnamed
    /// one) so the marker is still process-stable.
    static func syncedStoreURL(of container: ModelContainer) -> URL {
        container.configurations.first { $0.name == syncedConfigurationName }?.url
            ?? container.configurations.first?.url
            ?? URL(fileURLWithPath: "/dev/null")
    }
}
