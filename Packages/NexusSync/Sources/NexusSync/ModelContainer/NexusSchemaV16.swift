import Foundation
import NexusCore
import SwiftData

/// V16 schema: inbox activity feed state. Adds `FeedItemState` — mutable per-feed-item
/// UI state (seen / dismissed / snoozed), synced via CloudKit private DB.
///
/// The delta is lightweight-additive: one new table, NO data move, NO backfill.
/// `FeedItemState` carries no `@Attribute(.unique)` (CloudKit constraint), and every
/// property is defaulted or optional; SwiftData lightweight migration handles it.
public enum NexusSchemaV16: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV15.models + [FeedItemState.self]
    }

    /// Returns the V16 model list plus caller-supplied composition models,
    /// deduplicated by metatype identity (first occurrence wins).
    public static func assembledModels(extraModels: [any PersistentModel.Type] = []) -> [any PersistentModel.Type] {
        var seen = Set<ObjectIdentifier>()
        var assembled: [any PersistentModel.Type] = []

        for model in models + extraModels {
            let identifier = ObjectIdentifier(model)
            guard seen.insert(identifier).inserted else { continue }
            assembled.append(model)
        }

        return assembled
    }
}
