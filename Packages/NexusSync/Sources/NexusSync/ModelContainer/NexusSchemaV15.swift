import Foundation
import NexusCore
import SwiftData

/// V15 schema: universal project types. Adds the `Organization` (client/account) and
/// `ProjectKeyDate` (contract-anchor dates) entities, plus additive defaulted/optional
/// columns on `Project` (`typeRaw`/`stageRaw`/`clientID`/`vendor`/`customFieldsJSON`).
///
/// The delta is lightweight-additive: two new tables + new optional Project columns,
/// NO data move, NO backfill. Project's shape changes (new columns) but every new
/// column is optional/defaulted, so SwiftData lightweight migration handles it; the
/// `SchemaV*MigrationTests` suite is the gate.
public enum NexusSchemaV15: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(15, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        NexusSchemaV14.models + [Organization.self, ProjectKeyDate.self]
    }

    /// Returns the V15 model list plus caller-supplied composition models,
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
