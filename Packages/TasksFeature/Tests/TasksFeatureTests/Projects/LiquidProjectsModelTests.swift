import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("LiquidProjectsModel")
struct LiquidProjectsModelTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, TaskItem.self, Section.self, Note.self, Comment.self, Link.self, Cycle.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private struct RoadmapFixtures {
        let dated: Project
        let dateless: Project
        let liveSection: Section
    }

    private struct RoadmapSections {
        let live: Section
        let deleted: Section
        let foreign: Section
    }

    @MainActor
    private func insertRoadmapFixtures(in context: ModelContext, now: Date) -> RoadmapFixtures {
        let dated = Project(name: "Dated", color: "spark", status: .active)
        dated.createdAt = Self.date(2026, 6, 2)
        let dateless = Project(name: "Dateless", color: "leaf", status: .active)
        dateless.createdAt = Self.date(2026, 6, 5)
        let archived = Project(name: "Archived", color: "moon", status: .active)
        archived.createdAt = Self.date(2026, 6, 1)
        archived.archivedAt = now
        for project in [dated, dateless, archived] {
            context.insert(project)
        }

        let sections = insertRoadmapSections(in: context, dated: dated, dateless: dateless, now: now)
        insertRoadmapTasks(in: context, dated: dated, sections: sections)
        insertRoadmapCycles(in: context, now: now)
        return RoadmapFixtures(dated: dated, dateless: dateless, liveSection: sections.live)
    }

    @MainActor
    private func insertRoadmapSections(
        in context: ModelContext,
        dated: Project,
        dateless: Project,
        now: Date
    ) -> RoadmapSections {
        let liveSection = Section(projectID: dated.id, name: "Live milestone", orderIndex: 0)
        let deletedSection = Section(projectID: dated.id, name: "Deleted milestone", orderIndex: 1)
        deletedSection.deletedAt = now
        let foreignSection = Section(projectID: dateless.id, name: "Foreign milestone", orderIndex: 2)
        for section in [liveSection, deletedSection, foreignSection] {
            context.insert(section)
        }
        return RoadmapSections(live: liveSection, deleted: deletedSection, foreign: foreignSection)
    }

    @MainActor
    private func insertRoadmapTasks(
        in context: ModelContext,
        dated: Project,
        sections: RoadmapSections
    ) {
        context.insert(TaskItem(title: "Ship dated", dueAt: Self.date(2026, 6, 20), projectID: dated.id))
        context.insert(
            TaskItem(
                title: "Live section task",
                dueAt: Self.date(2026, 6, 18),
                projectID: dated.id,
                sectionID: sections.live.id
            )
        )
        context.insert(
            TaskItem(
                title: "Deleted section task",
                dueAt: Self.date(2026, 6, 19),
                projectID: dated.id,
                sectionID: sections.deleted.id
            )
        )
        context.insert(
            TaskItem(
                title: "Foreign section task",
                dueAt: Self.date(2026, 6, 17),
                projectID: dated.id,
                sectionID: sections.foreign.id
            )
        )
        context.insert(
            TaskItem(
                title: "Template should not move the bar",
                dueAt: Self.date(2026, 12, 31),
                projectID: dated.id,
                isTemplate: true
            )
        )
    }

    @MainActor
    private func insertRoadmapCycles(in context: ModelContext, now: Date) {
        context.insert(Cycle(name: "Sprint 1", startAt: Self.date(2026, 6, 9), endAt: Self.date(2026, 6, 22), status: .active))
        let deletedCycle = Cycle(
            name: "Deleted sprint",
            startAt: Self.date(2026, 6, 1),
            endAt: Self.date(2026, 6, 8),
            status: .completed
        )
        deletedCycle.deletedAt = now
        context.insert(deletedCycle)
    }

    /// The subtask count fetch is project-scoped IN-STORE via the `if let`
    /// optional-membership #Predicate (the `?? sentinel` coalescing form fails
    /// SQL generation at runtime) — this exercises the real SwiftData predicate
    /// translation (a runtime risk, not a compile-time one) and the grouping
    /// on top of it.
    @Test("Reload counts comments and subtasks per project task, scoped to the project")
    @MainActor
    func cardCountsAreProjectScoped() throws {
        let context = try makeContext()

        let project = Project(name: "P", status: .active)
        context.insert(project)

        let taskA = TaskItem(title: "A", projectID: project.id)
        let taskB = TaskItem(title: "B", projectID: project.id)
        let outsider = TaskItem(title: "outside")
        // Templates carry projectID verbatim but are inert (I-D1): never on the board.
        let template = TaskItem(title: "tpl", projectID: project.id, isTemplate: true)
        context.insert(taskA)
        context.insert(taskB)
        context.insert(outsider)
        context.insert(template)

        // Two live subtasks of A, one soft-deleted subtask of A (excluded),
        // one subtask of the non-project task (excluded), one parentless task.
        context.insert(TaskItem(title: "A.1", parentTaskID: taskA.id))
        context.insert(TaskItem(title: "A.2", parentTaskID: taskA.id))
        let deletedSub = TaskItem(title: "A.gone", parentTaskID: taskA.id)
        deletedSub.deletedAt = .now
        context.insert(deletedSub)
        context.insert(TaskItem(title: "out.1", parentTaskID: outsider.id))
        context.insert(TaskItem(title: "loner"))

        // One live comment on B, one deleted comment on B (excluded), one on
        // the outsider (excluded).
        context.insert(Comment(itemID: taskB.id, itemKind: .task, body: "hi"))
        let deletedComment = Comment(itemID: taskB.id, itemKind: .task, body: "gone")
        deletedComment.deletedAt = .now
        context.insert(deletedComment)
        context.insert(Comment(itemID: outsider.id, itemKind: .task, body: "elsewhere"))
        try context.save()

        let model = LiquidProjectsModel()
        model.selectedProjectID = project.id
        model.reload(modelContext: context)

        #expect(model.loadError == nil)
        #expect(model.selectedProject?.id == project.id)
        #expect(model.tasks.map(\.title).sorted() == ["A", "B"])
        #expect(model.subtaskCountsByTask == [taskA.id: 2])
        #expect(model.commentCountsByTask == [taskB.id: 1])
    }

    @Test("First line of the canonical note skips blank lines and trims")
    @MainActor
    func firstLineSkipsBlanks() {
        let note = Note(title: "t")
        note.plainText = "\n   \n  Build the next thing  \nsecond line"
        #expect(LiquidProjectsModel.firstLine(of: note) == "Build the next thing")
        #expect(LiquidProjectsModel.firstLine(of: nil) == nil)
    }

    @Test("Reload publishes roadmap project bars and cycle lane")
    @MainActor
    func reloadPublishesRoadmapFeed() throws {
        let context = try makeContext()
        let fixedNow = Self.date(2026, 6, 11, hour: 12)
        let fixtures = insertRoadmapFixtures(in: context, now: fixedNow)
        try context.save()

        let model = LiquidProjectsModel()
        model.reload(modelContext: context, now: fixedNow)

        #expect(model.loadError == nil)
        #expect(model.roadmapBars.map(\.name) == ["Dated", "Dateless"])
        #expect(model.roadmapBars.map(\.projectID) == [fixtures.dated.id, fixtures.dateless.id])
        #expect(model.roadmapBars.first?.start == Self.date(2026, 6, 2))
        #expect(model.roadmapBars.first?.end == Self.date(2026, 6, 20))
        #expect(model.roadmapBars.first?.milestones.map(\.sectionID) == [fixtures.liveSection.id])
        #expect(model.roadmapBars.first?.milestones.map(\.title) == ["Live milestone"])
        #expect(model.roadmapBars.first?.milestones.map(\.date) == [Self.date(2026, 6, 18)])
        #expect(model.roadmapBars.last?.start == Self.date(2026, 6, 5))
        #expect(model.roadmapBars.last?.end == nil)
        #expect(model.roadmapBars.last?.milestones == [])
        #expect(model.roadmapCycles.map(\.name) == ["Sprint 1"])
        #expect(model.roadmapCycles.map(\.status) == [.active])
    }

    @Test("Reference project snapshot supplies execution cockpit data")
    @MainActor
    func referenceProjectSnapshotIsDense() {
        let snapshot = LiquidProjectsReferenceData.snapshot(now: Self.date(2026, 6, 12, hour: 12))
        #expect(snapshot.project.name == "Product Roadmap")
        #expect(snapshot.tasks.count >= 12)
        #expect(snapshot.sections.count >= 4)
        #expect(snapshot.milestones.count >= 5)
        #expect(snapshot.risks.count >= 2)
        #expect(snapshot.activity.count >= 3)
        #expect(snapshot.progress > 0.5)
    }
}
