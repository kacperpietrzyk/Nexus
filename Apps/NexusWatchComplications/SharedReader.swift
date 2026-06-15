import Foundation
import NexusCore
import NexusSync
import SwiftData

struct WatchComplicationSnapshot: Sendable {
    let overdueCount: Int
    let todayCount: Int
    let firstUpcomingTitle: String?
    let firstUpcomingDueAt: Date?
    let firstUpcomingPriority: TaskPriority?
}

private struct WatchComplicationEnvironment: NexusEnvironmentProviding {
    var cloudKitEnabled: Bool { false }
    var cloudKitContainerIdentifier: String { NexusEnvironment.containerIdentifier }
}

enum SharedReader {
    @MainActor
    static func load(now: Date = .now) -> WatchComplicationSnapshot {
        do {
            let container = try NexusModelContainer.make(
                environment: WatchComplicationEnvironment(),
                groupContainerIdentifier: "group.com.kacperpietrzyk.Nexus"
            )
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.statusRaw == "open" && task.deletedAt == nil && task.dueAt != nil
                        && task.isTemplate == false
                },
                sortBy: [SortDescriptor(\.dueAt)]
            )
            let all = try context.fetch(descriptor)

            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: now)
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

            let overdue = all.filter { ($0.dueAt ?? .distantFuture) < startOfDay }
            let today = all.filter { task in
                guard let due = task.dueAt else { return false }
                return due >= startOfDay && due < startOfTomorrow
            }
            let upcoming = (overdue + today).first
            return WatchComplicationSnapshot(
                overdueCount: overdue.count,
                todayCount: today.count,
                firstUpcomingTitle: upcoming?.title,
                firstUpcomingDueAt: upcoming?.dueAt,
                firstUpcomingPriority: upcoming?.priority
            )
        } catch {
            return WatchComplicationSnapshot(
                overdueCount: 0,
                todayCount: 0,
                firstUpcomingTitle: nil,
                firstUpcomingDueAt: nil,
                firstUpcomingPriority: nil
            )
        }
    }
}
