import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

/// Regression suite for C1: a pinned project whose `status != .active` must
/// surface on the Today card. Before the fix, `loadStoreSnapshot` fed
/// `projectProgress` only `liveProjects.filter { $0.status == .active }`, so a
/// pinned backlog/planning project was dropped before `selectTodayProjects` saw
/// it. Fix: feed `active ∪ pinned` — status is irrelevant for pinned items.
@Suite("LiquidTodayModel pinned non-active projects (C1)")
struct LiquidTodayPinnedProjectTests {

    @Test("Pinned non-active project appears first on Today card (C1)")
    @MainActor
    func pinnedNonActiveProjectSurfacesOnTodayCard() async throws {
        let container = try ModelContainer(
            for: Project.self, TaskItem.self, Note.self, Link.self, ScheduledBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Pinned backlog project — would have been filtered out before the fix.
        let pinnedBacklog = Project(name: "PinnedBacklog", status: .backlog)
        pinnedBacklog.isPinned = true
        pinnedBacklog.pinnedAt = Date(timeIntervalSince1970: 5_000)
        pinnedBacklog.updatedAt = Date(timeIntervalSince1970: 1_000)

        // Active project with a more recent updatedAt — it would win under the
        // broken active-only filter, so if pinnedBacklog surfaces first the fix
        // is confirmed.
        let activeProject = Project(name: "ActiveProject", status: .active)
        activeProject.updatedAt = Date(timeIntervalSince1970: 8_000)

        context.insert(pinnedBacklog)
        context.insert(activeProject)
        try context.save()

        let model = LiquidTodayModel()
        await model.reload(
            modelContext: context,
            calendarProvider: MockCalendarEventProvider(status: .denied),
            calendarEventsEnabled: false,
            decisionsProvider: nil,
            briefProvider: nil,
            now: Date(timeIntervalSince1970: 10_000)
        )

        #expect(model.loadError == nil)
        #expect(
            model.projects.map(\.project.name).contains("PinnedBacklog"),
            "Pinned non-active project must appear on Today card"
        )
        #expect(
            model.projects.first?.project.name == "PinnedBacklog",
            "Pinned non-active project must sort ahead of active non-pinned projects"
        )
    }
}
