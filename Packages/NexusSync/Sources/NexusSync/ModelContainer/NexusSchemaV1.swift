import Foundation
import NexusCore
import SwiftData

/// Combined v1 schema for the on-disk container. Bundles the Core domain types (Link + DebugItem)
/// with sync-layer types (ConflictLog). When new domain modules ship (Note/Task/Meeting/Project),
/// append their types here and bump the schema version.
public enum NexusSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Link.self,
            DebugItem.self,
            ConflictLog.self,
        ]
    }
}
