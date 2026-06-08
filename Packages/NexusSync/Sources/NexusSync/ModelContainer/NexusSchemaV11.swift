import Foundation
import NexusCore
import SwiftData

/// V11 schema: extends V10 with the `Label` entity (Projects tier — the structural
/// label layer, spec §4.4/§12). A `Label` is a synced first-class graph entity
/// (`ItemKind.label`) attached to tasks and projects through the `Link` graph
/// (`LinkKind.labeled`, never a SwiftData `@Relationship` — decision D7).
///
/// Three additive fields on existing live models land alongside it and are part of
/// the same lightweight-additive V10 → V11 delta:
/// `Project.statusRaw: String` (defaulted `ProjectStatus.backlog.rawValue`),
/// `TaskItem.workflowStateRaw: String?` (nil = GTD task), and
/// `TaskItem.assignedAgent: String?` (nil = self). All three are already declared
/// on the live `Project`/`TaskItem` classes, so the in-code V10 and V11 schemas
/// both reference classes carrying those columns; on a shipped-V10 on-disk store
/// the columns are physically absent and the V11 build's lightweight inference adds
/// them in the same pass that adds the `Label` table. No V11-specific data move is
/// required — the whole V10 → V11 delta is lightweight-additive, so
/// `NexusMigrationPlan`'s V10 → V11 stage is `.lightweight`.
///
/// The system-label SEED (feature/bug/infra/security + needsDecision/decided,
/// `isSystem = true`) is NOT a migration stage: like the V8 → V9 body → Note move
/// it runs as plain, idempotent, marker-gated post-open code on the already-open
/// split container — see `NexusModelContainer.seedSystemLabelsIfNeeded`.
public enum NexusSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV10.models + [Label.self]
    }

    /// Returns the V11 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline or
    /// repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V11 list.
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
