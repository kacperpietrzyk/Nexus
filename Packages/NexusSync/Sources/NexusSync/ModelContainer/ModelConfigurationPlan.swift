import Foundation
import SwiftData

/// The partitioned model lists for the split (synced + local-only) container.
///
/// `containerModels` is the full assembled set; `syncedModels` mirror to CloudKit;
/// `localOnlyModels` stay device-local (`ConflictLog`, `ModelManifest`, plus any
/// composition-time local-only extras). `hasEffectiveExtraModels` records whether
/// composition added models beyond the current versioned-schema baseline — which
/// forces the inference open path in `NexusModelContainer.makeContainer`.
struct ModelPartitions {
    let containerModels: [any PersistentModel.Type]
    let syncedModels: [any PersistentModel.Type]
    let localOnlyModels: [any PersistentModel.Type]
    let hasEffectiveExtraModels: Bool
}

/// The assembled schema + configurations + partitions for one container open,
/// produced by `NexusModelContainer.makeConfigurationPlan`.
struct ModelConfigurationPlan {
    let containerSchema: Schema
    let configurations: [ModelConfiguration]
    let partitions: ModelPartitions

    var hasEffectiveExtraModels: Bool {
        partitions.hasEffectiveExtraModels
    }
}
