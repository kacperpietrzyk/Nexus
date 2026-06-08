#if DEBUG
import Foundation
import NexusCore
import SwiftData

/// Debug-only demo seeder for visual/QA work. Gated on the `NEXUS_SEED_DEMO=1`
/// launch environment variable so it never runs in normal Debug launches, and
/// only seeds when the task store is empty (idempotent across relaunches).
///
/// Not compiled into Release. Mirrors the iOS seeder so the macOS Tasks/Notes
/// surfaces can be screenshot-driven during the visual-polish loop.
enum DebugDemoSeed {
    @MainActor
    static func seedIfRequested(context: ModelContext, noteRepository: NoteRepository) {
        guard ProcessInfo.processInfo.environment["NEXUS_SEED_DEMO"] == "1" else { return }

        let existing = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        guard existing.allSatisfy({ $0.deletedAt != nil }) else { return }

        let calendar = Calendar.current
        let now = Date.now
        func day(_ delta: Int) -> Date {
            calendar.date(byAdding: .day, value: delta, to: now) ?? now
        }

        let tasks: [TaskItem] = [
            TaskItem(
                title: "Reply to Magda about the Q3 roadmap deck and the revised budget numbers",
                dueAt: day(-2), priority: .high, tags: ["email", "work", "urgent"]),
            TaskItem(title: "Review pull request #482", dueAt: now, priority: .medium, tags: ["dev"]),
            TaskItem(title: "Book dentist appointment", dueAt: day(1), priority: .low, tags: ["health"]),
            TaskItem(
                title: "Prepare slides for Monday standup", dueAt: day(3), deadlineAt: day(3),
                priority: .high, tags: ["work"]),
            TaskItem(title: "Buy groceries", priority: .none, tags: ["home"]),
            TaskItem(
                title: "Weekly review", dueAt: day(2), priority: .medium,
                tags: ["routine"], recurrenceRule: "FREQ=WEEKLY"),
            TaskItem(title: "Call the bank about the wire transfer", dueAt: day(-1), priority: .medium, tags: ["finance", "phone"]),
            TaskItem(
                title: "Read 'Designing Data-Intensive Applications' chapter 5",
                priority: .low, tags: ["reading", "learning", "books"]),
        ]
        for task in tasks { context.insert(task) }
        try? context.save()

        _ = try? noteRepository.create(title: "Project Nexus — north star", tags: ["product"])
        _ = try? noteRepository.create(title: "Meeting notes: design sync", tags: ["meeting"])
        _ = try? noteRepository.create(title: "Reading list", tags: ["personal"])
        _ = try? noteRepository.create(title: "Weekend trip ideas", tags: ["personal", "travel"])
    }
}
#endif
