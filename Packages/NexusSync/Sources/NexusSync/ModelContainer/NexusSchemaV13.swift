import Foundation
import NexusCore
import SwiftData

/// V13 schema: extends V12 with the Tranche-2 parity batch (spec
/// `2026-06-11-tranche2-v8-parity-batch.md`): the `Cycle` sprint entity
/// (Linear L1) and the `ActivityEntry` append-only audit-log entity (Linear
/// L3 / Todoist T6) as new tables, plus four additive defaulted/optional
/// columns on existing models — `TaskItem.cycleID` / `TaskItem.isTemplate`
/// (Todoist T2) and `Note.propertiesJSON` / `Note.folderPath` (Obsidian
/// O6/O2).
///
/// The whole V12 → V13 delta is lightweight-additive: two new tables + four
/// additive defaulted/optional columns. The new `ItemKind.cycle` /
/// `NoteRole.template` raw enum cases ride existing `String`-backed columns
/// and need no schema change (the V12 `ItemKind.person` precedent). There is
/// NO data move and NO backfill — every new field starts nil/defaulted and
/// every new table starts empty — so `NexusMigrationPlan`'s V12 → V13 stage
/// is `.lightweight` and, unlike V9 (body → Note move), V11 (label seed), and
/// V12 (people backfill), this bump adds NO marker-gated post-open bootstrap
/// step.
public enum NexusSchemaV13: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV12.models + [Cycle.self, ActivityEntry.self]
    }

    /// Returns the V13 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline
    /// or repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V13 list.
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
