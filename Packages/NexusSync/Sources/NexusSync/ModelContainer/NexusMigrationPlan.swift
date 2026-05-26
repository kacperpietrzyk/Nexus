import Foundation
import NexusCore
import SwiftData

/// Schema migration plan for the on-disk container.
///
/// Stages:
/// - V1 -> V2 lightweight (additive: `QuotaLog`).
/// - V2 -> V3 lightweight (additive: `TaskItem`; `DebugItem` retained vestigial).
/// - V3 -> V4 lightweight (additive: `TaskItem` external-source fields).
/// - V4 -> V5 lightweight (additive: `TaskItem.endAt`).
/// - V5 -> V6 lightweight (additive: task hierarchy/deadline/project fields and
///   Project/Section/SavedFilter entities).
/// - V6 -> V7 lightweight (additive: ModelManifest, ModelDownloadEvent).
public enum NexusMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            NexusSchemaV1.self,
            NexusSchemaV2.self,
            NexusSchemaV3.self,
            NexusSchemaV4.self,
            NexusSchemaV5.self,
            NexusSchemaV6.self,
            NexusSchemaV7.self,
        ]
    }

    public static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV1.self,
                toVersion: NexusSchemaV2.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV2.self,
                toVersion: NexusSchemaV3.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV3.self,
                toVersion: NexusSchemaV4.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV4.self,
                toVersion: NexusSchemaV5.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV5.self,
                toVersion: NexusSchemaV6.self
            ),
            MigrationStage.lightweight(
                fromVersion: NexusSchemaV6.self,
                toVersion: NexusSchemaV7.self
            ),
        ]
    }
}
