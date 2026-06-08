import Foundation
import NexusCore
import SwiftData

/// V12 schema: extends V11 with the `Person` entity (People / Contacts module,
/// spec §4.1/§8). A `Person` is a synced first-class graph entity
/// (`ItemKind.person`) — a lightweight single-user contact RECORD (like a row in
/// Apple Contacts), never a task assignee (invariant I1). It aggregates
/// "everything about a person" purely through the polymorphic `Link` graph
/// (`LinkKind.attendee` for meetings, reused `LinkKind.mentions` for tasks/notes —
/// never a SwiftData `@Relationship`).
///
/// The whole V11 → V12 delta is lightweight-additive: a shipped-V11 on-disk store
/// physically lacks the `Person` table; the V12 build's lightweight inference adds
/// it in one pass. There is NO data move and NO additive column on an existing
/// live model — the new `ItemKind.person` / `LinkKind.attendee` raw enum cases are
/// stored as `String` columns on the existing `Link` table and require no schema
/// change. So `NexusMigrationPlan`'s V11 → V12 stage is `.lightweight`.
///
/// The optional `participantsJSON` → `Person` BACKFILL (spec §8) is NOT a migration
/// stage: like the V8 → V9 body → Note move and the V11 system-label seed, it runs
/// as plain, idempotent, marker-gated code over an already-open container. It is
/// deferred to first-launch bootstrap because it needs the concrete `Meeting` type
/// (a composition-time extra NexusSync cannot import) — see
/// `NexusMigrationPlan.backfillPeopleFromMeetingParticipants`.
public enum NexusSchemaV12: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(12, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV11.models + [Person.self]
    }

    /// Returns the V12 model list plus caller-supplied composition models.
    ///
    /// `extraModels` is for higher-level packages that cannot be imported by
    /// NexusSync without creating a package cycle. Callers may pass baseline or
    /// repeated models; this helper deduplicates by metatype identity while
    /// preserving the first occurrence order from the baseline V12 list.
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
