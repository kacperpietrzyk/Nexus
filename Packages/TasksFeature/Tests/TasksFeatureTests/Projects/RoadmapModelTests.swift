import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("RoadmapModel derivations")
struct RoadmapModelTests {

    // MARK: - Fixtures

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let now = date(2026, 6, 11, hour: 12)

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, TaskItem.self, Section.self, Cycle.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makeProject(_ context: ModelContext, name: String = "P", createdAt: Date) -> Project {
        let project = Project(name: name, color: "spark")
        project.createdAt = createdAt
        context.insert(project)
        return project
    }

    @MainActor
    private func makeSection(_ context: ModelContext, projectID: UUID, name: String, orderIndex: Double) -> Section {
        let section = Section(projectID: projectID, name: name, orderIndex: orderIndex)
        context.insert(section)
        return section
    }

    @MainActor
    private func makeTask(
        _ context: ModelContext,
        title: String,
        projectID: UUID,
        status: TaskStatus = .open,
        startAt: Date? = nil,
        dueAt: Date? = nil,
        deadlineAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        sectionID: UUID? = nil,
        deletedAt: Date? = nil,
        isTemplate: Bool = false
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            dueAt: dueAt,
            startAt: startAt,
            deadlineAt: deadlineAt,
            status: status,
            projectID: projectID,
            sectionID: sectionID,
            isTemplate: isTemplate
        )
        task.lastCompletedAt = lastCompletedAt
        task.deletedAt = deletedAt
        context.insert(task)
        return task
    }

    // MARK: - Project span

    @Test("Bar start is earliest of createdAt / task startAt / task dueAt; end is latest due or deadline")
    @MainActor
    func spanDerivation() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 5))
        let tasks = [
            makeTask(context, title: "a", projectID: project.id, startAt: Self.date(2026, 6, 1), dueAt: Self.date(2026, 6, 9)),
            makeTask(context, title: "b", projectID: project.id, dueAt: Self.date(2026, 6, 20), deadlineAt: Self.date(2026, 6, 25)),
        ]

        let bar = RoadmapModel.bar(project: project, tasks: tasks, sections: [], now: Self.now)

        #expect(bar.projectID == project.id)
        #expect(bar.name == "P")
        #expect(bar.glyphToken == "spark")
        #expect(bar.id == project.id)
        #expect(bar.start == Self.date(2026, 6, 1))
        #expect(bar.end == Self.date(2026, 6, 25))
    }

    @Test("Deleted and template tasks never move the span")
    @MainActor
    func spanIgnoresDeletedAndTemplates() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 5))
        let tasks = [
            makeTask(context, title: "live", projectID: project.id, dueAt: Self.date(2026, 6, 10)),
            makeTask(
                context, title: "deleted", projectID: project.id, startAt: Self.date(2026, 5, 1),
                deadlineAt: Self.date(2026, 8, 1),
                deletedAt: Self.now
            ),
            makeTask(
                context, title: "template", projectID: project.id, startAt: Self.date(2026, 4, 1),
                deadlineAt: Self.date(2026, 9, 1),
                isTemplate: true
            ),
        ]

        let bar = RoadmapModel.bar(project: project, tasks: tasks, sections: [], now: Self.now)

        #expect(bar.start == Self.date(2026, 6, 5))
        #expect(bar.end == Self.date(2026, 6, 10))
    }

    @Test("No dated live task gives an open-ended bar starting at createdAt")
    @MainActor
    func openEndedWithoutDatedTasks() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 5))
        let tasks = [makeTask(context, title: "undated", projectID: project.id)]

        let bar = RoadmapModel.bar(project: project, tasks: tasks, sections: [], now: Self.now)

        #expect(bar.start == Self.date(2026, 6, 5))
        #expect(bar.end == nil)
    }

    @Test("A derived end behind start clamps to start")
    @MainActor
    func endBehindStartClamps() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 20))
        let tasks = [
            makeTask(context, title: "deadline only", projectID: project.id, deadlineAt: Self.date(2026, 6, 1))
        ]

        let bar = RoadmapModel.bar(project: project, tasks: tasks, sections: [], now: Self.now)

        #expect(bar.start == Self.date(2026, 6, 20))
        #expect(bar.end == Self.date(2026, 6, 20))
    }

    @Test("Health and progress are delegated to ProjectExecutionModel over live non-template tasks")
    @MainActor
    func healthAndProgressMatchExecutionModel() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 5))
        let live = [
            makeTask(context, title: "done", projectID: project.id, status: .done),
            makeTask(context, title: "open", projectID: project.id, dueAt: Self.date(2026, 6, 1)),
        ]
        let ignored = [
            makeTask(context, title: "deleted", projectID: project.id, status: .done, deletedAt: Self.now),
            makeTask(context, title: "template", projectID: project.id, status: .done, isTemplate: true),
        ]

        let bar = RoadmapModel.bar(project: project, tasks: live + ignored, sections: [], now: Self.now)

        #expect(bar.health == ProjectExecutionModel.health(tasks: live, now: Self.now))
        #expect(bar.progress == ProjectExecutionModel.progress(tasks: live))
    }

    // MARK: - Milestones

    @Test("Milestone markers derive dates and state from section milestones")
    @MainActor
    func milestoneMarkers() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 1))
        let done = makeSection(context, projectID: project.id, name: "Done", orderIndex: 0)
        let active = makeSection(context, projectID: project.id, name: "Active", orderIndex: 1)
        let upcoming = makeSection(context, projectID: project.id, name: "Upcoming", orderIndex: 2)
        let undatable = makeSection(context, projectID: project.id, name: "Undated", orderIndex: 3)

        let tasks = [
            makeTask(
                context,
                title: "deadline wins",
                projectID: project.id,
                status: .done,
                dueAt: Self.date(2026, 6, 4),
                deadlineAt: Self.date(2026, 6, 6),
                lastCompletedAt: Self.date(2026, 6, 8),
                sectionID: done.id
            ),
            makeTask(
                context,
                title: "done completion fallback",
                projectID: project.id,
                status: .done,
                lastCompletedAt: Self.date(2026, 6, 9),
                sectionID: done.id
            ),
            makeTask(
                context,
                title: "due fallback",
                projectID: project.id,
                dueAt: Self.date(2026, 6, 7),
                sectionID: active.id
            ),
            makeTask(
                context,
                title: "open completion ignored",
                projectID: project.id,
                lastCompletedAt: Self.date(2026, 6, 30),
                sectionID: active.id
            ),
            makeTask(context, title: "future", projectID: project.id, dueAt: Self.date(2026, 6, 20), sectionID: upcoming.id),
            makeTask(context, title: "undated", projectID: project.id, sectionID: undatable.id),
        ]

        let bar = RoadmapModel.bar(
            project: project,
            tasks: tasks,
            sections: [undatable, active, upcoming, done],
            now: Self.now
        )

        #expect(bar.milestones.map(\.sectionID) == [done.id, active.id, upcoming.id])
        #expect(bar.milestones.map(\.id) == [done.id, active.id, upcoming.id])
        #expect(bar.milestones.map(\.title) == ["Done", "Active", "Upcoming"])
        #expect(bar.milestones.map(\.date) == [Self.date(2026, 6, 9), Self.date(2026, 6, 7), Self.date(2026, 6, 20)])
        #expect(bar.milestones.map(\.state) == [.completed, .upcoming, .upcoming])
    }

    @Test("Tasks from another project cannot move span, health, progress, or milestones")
    @MainActor
    func foreignTasksAreIgnored() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 10))
        let other = makeProject(context, name: "Other", createdAt: Self.date(2026, 1, 1))
        let section = makeSection(context, projectID: project.id, name: "Owned", orderIndex: 0)
        let owned = makeTask(
            context,
            title: "owned",
            projectID: project.id,
            dueAt: Self.date(2026, 6, 15),
            sectionID: section.id
        )
        let foreign = makeTask(
            context,
            title: "foreign",
            projectID: other.id,
            status: .done,
            startAt: Self.date(2026, 5, 1),
            dueAt: Self.date(2026, 5, 2),
            deadlineAt: Self.date(2026, 8, 1),
            sectionID: section.id
        )

        let bar = RoadmapModel.bar(project: project, tasks: [owned, foreign], sections: [section], now: Self.now)

        #expect(bar.start == Self.date(2026, 6, 10))
        #expect(bar.end == Self.date(2026, 6, 15))
        #expect(bar.health == ProjectExecutionModel.health(tasks: [owned], now: Self.now))
        #expect(bar.progress == ProjectExecutionModel.progress(tasks: [owned]))
        #expect(
            bar.milestones == [
                RoadmapModel.MilestoneMarker(sectionID: section.id, title: "Owned", date: Self.date(2026, 6, 15), state: .upcoming)
            ])
    }

    @Test("Deleted and foreign sections do not produce milestone markers")
    @MainActor
    func deletedAndForeignSectionsDoNotProduceMarkers() throws {
        let context = try makeContext()
        let project = makeProject(context, createdAt: Self.date(2026, 6, 1))
        let other = makeProject(context, name: "Other", createdAt: Self.date(2026, 6, 1))
        let live = makeSection(context, projectID: project.id, name: "Live", orderIndex: 0)
        let deleted = makeSection(context, projectID: project.id, name: "Deleted", orderIndex: 1)
        deleted.deletedAt = Self.now
        let foreign = makeSection(context, projectID: other.id, name: "Foreign", orderIndex: 2)
        let tasks = [
            makeTask(context, title: "live", projectID: project.id, dueAt: Self.date(2026, 6, 5), sectionID: live.id),
            makeTask(context, title: "deleted", projectID: project.id, dueAt: Self.date(2026, 6, 6), sectionID: deleted.id),
            makeTask(context, title: "foreign", projectID: project.id, dueAt: Self.date(2026, 6, 7), sectionID: foreign.id),
        ]

        let bar = RoadmapModel.bar(project: project, tasks: tasks, sections: [deleted, foreign, live], now: Self.now)

        #expect(
            bar.milestones == [
                RoadmapModel.MilestoneMarker(sectionID: live.id, title: "Live", date: Self.date(2026, 6, 5), state: .upcoming)
            ])
    }

    // MARK: - Cycles

    // MARK: - Key dates

    @MainActor
    @Test func keyDatesExtendSpanAndProduceMarkers() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let project = Project(name: "P", color: "azure")
        project.createdAt = now
        let kdEarly = ProjectKeyDate(
            projectID: project.id, anchorKey: "kickoff", label: "Kickoff",
            date: now.addingTimeInterval(-10 * 86_400))
        let kdLate = ProjectKeyDate(
            projectID: project.id, anchorKey: "golive", label: "Go-live",
            date: now.addingTimeInterval(30 * 86_400), isContractual: true)
        let bar = RoadmapModel.bar(project: project, tasks: [], sections: [], keyDates: [kdEarly, kdLate], now: now)
        #expect(bar.start <= kdEarly.date)  // early key date pulls the start back
        #expect(bar.end == kdLate.date)  // late key date sets the end
        #expect(bar.scheduled == true)
        #expect(bar.keyDates.count == 2)
        #expect(bar.keyDates.contains { $0.label == "Go-live" && $0.isContractual })
    }

    @MainActor
    @Test func noDatesProjectIsUnscheduled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let project = Project(name: "P", color: "azure")
        project.createdAt = now
        let bar = RoadmapModel.bar(project: project, tasks: [], sections: [], keyDates: [], now: now)
        #expect(bar.scheduled == false)
        #expect(bar.end == nil)
        #expect(bar.keyDates.isEmpty)
    }

    // MARK: - Cycles

    @Test("Cycle bars ignore deleted cycles and sort by startAt then id")
    @MainActor
    func cycleBars() throws {
        let context = try makeContext()
        let later = Cycle(name: "Later", startAt: Self.date(2026, 7, 1), endAt: Self.date(2026, 7, 14), status: .upcoming)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let tiedSecond = Cycle(
            id: secondID, name: "Tie 2", startAt: Self.date(2026, 6, 1), endAt: Self.date(2026, 6, 14), status: .active
        )
        let tiedFirst = Cycle(
            id: firstID, name: "Tie 1", startAt: Self.date(2026, 6, 1), endAt: Self.date(2026, 6, 14), status: .active
        )
        let deleted = Cycle(name: "Deleted", startAt: Self.date(2026, 5, 1), endAt: Self.date(2026, 5, 14), status: .completed)
        deleted.deletedAt = Self.now
        for cycle in [later, tiedSecond, tiedFirst, deleted] {
            context.insert(cycle)
        }

        let bars = RoadmapModel.cycleBars([later, tiedSecond, tiedFirst, deleted])

        #expect(bars.map(\.cycleID) == [firstID, secondID, later.id])
        #expect(bars.map(\.id) == [firstID, secondID, later.id])
        #expect(bars.map(\.name) == ["Tie 1", "Tie 2", "Later"])
        #expect(bars.map(\.status) == [.active, .active, .upcoming])
    }
}
