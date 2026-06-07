import Foundation

/// Lifecycle state of a `ScheduledBlock`. Stored on `ScheduledBlock.statusRaw`
/// as `String` because SwiftData + CloudKit mirroring rejects enum-typed model
/// properties. Stable raw values — these land in CloudKit and must NEVER be
/// renamed without a migration.
///
/// A `proposed` block lives only inside Nexus (no mirror event yet). It becomes
/// `accepted` once the user accepts it and a mirror `EKEvent` is written to the
/// dedicated "Nexus" calendar (invariant §14: `accepted ⇒ externalEventID != nil`).
public enum ScheduledBlockStatus: String, Codable, Sendable, CaseIterable {
    case proposed
    case accepted
}
