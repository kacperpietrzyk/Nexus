import Foundation
import NexusCore
import SwiftData

/// V9 schema: extends V8 with the `Note` entity (the universal content layer —
/// Notes module, spec §15). Two additive fields on existing live models land with
/// it: `TaskItem.noteRef` and `Project.canonicalNoteRef` (both `UUID?`, defaulted
/// nil → lightweight-additive).
///
/// DATA-SAFETY — two-step retirement of `TaskItem.body` (spec §2/§15, CRITICAL
/// engineering decision): the spec calls for `TaskItem.body` to be *removed* in
/// V9. Because the versioned schemas in this project all reference the LIVE
/// `@Model` classes (this enum's `models` is `NexusSchemaV8.models + [Note.self]`,
/// where `TaskItem.self` is the same class the app uses), the body→Note
/// conversion CANNOT read a property that has been physically deleted from the
/// shared class — and existing users' note content would be silently lost on the
/// first V9 launch. Therefore `TaskItem.body` is KEPT physically present (marked
/// LEGACY in `TaskItem`), and the conversion (see
/// `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded`) reads the still-present
/// column to mint `Note`s. App logic no longer reads `body` — all readers repoint
/// onto `noteRef`. The physical column is retired in a *later* schema, once this
/// V9 migration is proven in the field.
///
/// The V8→V9 SCHEMA delta is lightweight-additive (Note table + two `UUID?` ref
/// fields), so `NexusMigrationPlan`'s V8→V9 stage is `.lightweight`. The
/// `body`→`Note` DATA move is NOT a migration stage: a `.custom` stage cannot run
/// on the production split container (which drops the plan and infers), and a
/// plan-driven open throws on any store carrying composition extras (Meeting). It
/// runs instead as plain, idempotent, marker-gated post-open code — see
/// `NexusModelContainer.migrateTaskBodiesToNotesIfNeeded` and `NexusMigrationPlan`.
public enum NexusSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV8.models + [Note.self]
    }

    /// Returns the V9 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline or
    /// repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V9 list.
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
