import Foundation
import SwiftData

/// Factory namespace that turns the existing `TombstonePurger` `@ModelActor` into a `ScheduledJob`
/// the scheduler can register. Spawns a fresh purger per run so there's no long-lived ModelActor
/// tied to a stale ModelContainer reference.
public enum TombstonePurgeJob {
    public static let dailyInterval: TimeInterval = 60 * 60 * 24

    /// - Parameters:
    ///   - container: the live ModelContainer; captured by the run closure.
    ///   - retention: tombstones older than this are hard-deleted. Defaults to 30 days.
    ///   - linkableTypes: concrete Linkable types to purge.
    public static func make(
        container: ModelContainer,
        retention: TimeInterval = TombstonePurger.defaultRetention,
        linkableTypes: [any Linkable.Type]
    ) -> ScheduledJob {
        ScheduledJob(id: .tombstonePurge, interval: dailyInterval) { now in
            let purger = TombstonePurger(modelContainer: container)
            _ = try await purger.purge(olderThan: retention, now: now, types: linkableTypes)
        }
    }
}
