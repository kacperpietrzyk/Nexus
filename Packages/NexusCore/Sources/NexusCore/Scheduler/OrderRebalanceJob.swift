import Foundation
import SwiftData

/// Periodic job that renormalises `TaskItem.orderIndex` to `1.0, 2.0, 3.0, …`
/// in ascending order. Counters drag-drop midpoint drift (`(prev + next) / 2`
/// approaches degenerate floats after ~1000 reorders). Mirrors the
/// `TombstonePurgeJob` pattern: spawns a fresh ModelContext per run so there's
/// no long-lived reference to a stale ModelContainer.
public enum OrderRebalanceJob {
    public static let dailyInterval: TimeInterval = 60 * 60 * 24

    /// - Parameter containerProvider: closure that returns the live `ModelContainer`.
    ///   Captured by the run closure and invoked once per scheduler tick.
    public static func makeJob(
        containerProvider: @escaping @Sendable () -> ModelContainer
    ) -> ScheduledJob {
        ScheduledJob(id: .orderRebalance, interval: dailyInterval) { _ in
            let container = containerProvider()
            try await renumber(in: container)
        }
    }

    @MainActor
    static func renumber(in container: ModelContainer) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in task.orderIndex != nil },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        let tasks = try context.fetch(descriptor)
        for (index, task) in tasks.enumerated() {
            task.orderIndex = Double(index + 1)
        }
        try context.save()
    }
}
