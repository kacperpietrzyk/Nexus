import Foundation
import NexusCore
import SwiftData

/// V7 schema: extends V6 with the MLX model catalog entities `ModelManifest`
/// and `ModelDownloadEvent` (both NexusCore-owned baseline `@Model` types, like
/// `TaskItem`/`Link`/`Project`). Lightweight additive migration from V6.
///
/// Per Phase 1l decision (2026-05-15, option B): a real `NexusSchemaV7` rather
/// than an in-place V6 extension. The catalog seed (`ModelCatalog.bootstrap`)
/// runs idempotently from the composition root, NOT in a `didMigrate` closure —
/// NexusSync cannot import `ModelCatalog` (it lives in NexusAI, which already
/// depends on NexusSync; importing it back would be a SwiftPM package cycle).
public enum NexusSchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV6.models + [ModelManifest.self, ModelDownloadEvent.self]
    }

    /// Returns the V7 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline or
    /// repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V7 list.
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
