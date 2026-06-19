import Foundation
import NexusCore
import SwiftData

/// V17 schema: durable agent insights. Adds `AgentInsightRecord` — a persisted
/// agent proposal awaiting user confirmation, stored as encoded JSON so the
/// confirm flow survives a relaunch. Synced via CloudKit private DB.
///
/// The delta is lightweight-additive: one new table, NO data move, NO backfill.
/// `AgentInsightRecord` carries no `@Attribute(.unique)` (CloudKit constraint),
/// and every property is defaulted or optional; SwiftData lightweight migration
/// handles it.
public enum NexusSchemaV17: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(17, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV16.models + [AgentInsightRecord.self]
    }

    /// Returns the V17 model list plus caller-supplied composition models,
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
