import Foundation
import NexusCore
import SwiftData

/// V14 schema: adds durable attachment metadata for O5 image attachments.
///
/// The delta is lightweight-additive: one new table, no data move, no backfill.
public enum NexusSchemaV14: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV13.models + [AttachmentAsset.self]
    }

    /// Returns the V14 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline
    /// or repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V14 list.
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
