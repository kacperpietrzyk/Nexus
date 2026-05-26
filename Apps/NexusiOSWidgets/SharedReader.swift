import Foundation
import NexusCore
import NexusSync
import SwiftData

/// Snapshot value type the widget views render. Produced by `SharedReader.load(now:)`
/// against the App Group SwiftData store the main app writes to.
struct WidgetSnapshot: Sendable {
    let overdueCount: Int
    let todayCount: Int
    let noDateCount: Int
    let firstOverdueTitle: String?
    let firstTodayTitles: [String]
}

/// Stub `NexusEnvironmentProviding` so the widget extension can construct the shared
/// container without tripping the CloudKit path. The main app owns CloudKit sync;
/// the widget only reads the local mirror.
private struct WidgetEnvironment: NexusEnvironmentProviding {
    var cloudKitEnabled: Bool { false }
    var cloudKitContainerIdentifier: String { NexusEnvironment.containerIdentifier }
}

/// Opens the App Group SwiftData store, fetches open `TaskItem`s, and bins them
/// into (overdue, today, noDate). Uses `NexusModelContainer.make(...)` for path
/// coordination with the main app's container — bare `ModelConfiguration(schema:groupContainer:)`
/// would land at a different path inside the App Group and silently read zero data.
enum SharedReader {
    @MainActor
    static func load(now: Date = .now) -> WidgetSnapshot {
        do {
            let container = try NexusModelContainer.make(
                environment: WidgetEnvironment(),
                groupContainerIdentifier: "group.com.kacperpietrzyk.Nexus"
            )
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.statusRaw == "open" && task.deletedAt == nil
                },
                sortBy: [SortDescriptor(\.dueAt)]
            )
            let all = try context.fetch(descriptor)
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: now)
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            let overdue = all.filter { task in
                guard let due = task.dueAt else { return false }
                return due < startOfToday
            }
            let today = all.filter { task in
                guard let due = task.dueAt else { return false }
                return due >= startOfToday && due < endOfToday
            }
            let noDate = all.filter { $0.dueAt == nil }
            return WidgetSnapshot(
                overdueCount: overdue.count,
                todayCount: today.count,
                noDateCount: noDate.count,
                firstOverdueTitle: overdue.first?.title,
                firstTodayTitles: today.prefix(3).map(\.title)
            )
        } catch {
            return WidgetSnapshot(
                overdueCount: 0,
                todayCount: 0,
                noDateCount: 0,
                firstOverdueTitle: nil,
                firstTodayTitles: []
            )
        }
    }
}
