import Foundation
import NexusCore
import SwiftData

/// V2 schema: adds `QuotaLog` for persistent AI usage tracking (Phase 1a).
/// V1 → V2 is a lightweight, additive migration — no data transformation required.
///
/// `DebugItem` is intentionally retained in V2 because Phase 1b creates V3 that
/// removes it together with adding `Task`. Keeping the staged migration explicit
/// avoids "what was V2 again?" confusion when reading history.
public enum NexusSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Link.self,
            DebugItem.self,
            ConflictLog.self,
            QuotaLog.self,
        ]
    }
}
