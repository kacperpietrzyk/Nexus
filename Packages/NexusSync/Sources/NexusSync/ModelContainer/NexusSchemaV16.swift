import Foundation
import NexusCore
import SwiftData

/// V16 schema: pin/favorite fields on Project, Note, and Meeting. Adds
/// `isPinned: Bool` and `pinnedAt: Date?` to each of those three entities.
///
/// The delta is lightweight-additive: no new tables, no data move, no backfill.
/// Every new column is defaulted (`false`) or optional (`nil`), so SwiftData
/// lightweight migration handles it without a custom stage.
public enum NexusSchemaV16: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV15.models  // additive property bump; same entity set as V15
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

    static func hasEffectiveExtraModels(_ extraModels: [any PersistentModel.Type]) -> Bool {
        assembledModels(extraModels: extraModels).count > models.count
    }

    public static func schema(extraModels: [any PersistentModel.Type] = []) -> Schema {
        let assembledModels = assembledModels(extraModels: extraModels)
        guard assembledModels.count > models.count else {
            return Schema(versionedSchema: Self.self)
        }
        return Schema(assembledModels, version: versionIdentifier)
    }
}
