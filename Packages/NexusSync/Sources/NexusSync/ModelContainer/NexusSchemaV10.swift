import Foundation
import NexusCore
import SwiftData

/// V10 schema: extends V9 with the `ScheduledBlock` entity (Calendar / Motion-AI
/// scheduler module, spec §3/§4.1/§15). A `ScheduledBlock` is a synced first-class
/// graph entity (`ItemKind.scheduledBlock`) holding a proposed/accepted time block
/// for a `TaskItem`.
///
/// Two additive fields on the existing live `TaskItem` land alongside it:
/// `estimatedDurationSeconds: Int?` and `durationSourceRaw: String?` (spec §5).
/// Both are already declared on the live `TaskItem` class, so the in-code V9 and
/// V10 schemas both reference a class carrying those columns; on a shipped-V9
/// on-disk store the columns are physically absent and the V10 build's
/// lightweight inference adds them in the same pass that adds the `ScheduledBlock`
/// table. No V10-specific data move is required — the whole V9 → V10 delta is
/// lightweight-additive, so `NexusMigrationPlan`'s V9 → V10 stage is `.lightweight`.
public enum NexusSchemaV10: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV9.models + [ScheduledBlock.self]
    }

    /// Returns the V10 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline or
    /// repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V10 list.
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
