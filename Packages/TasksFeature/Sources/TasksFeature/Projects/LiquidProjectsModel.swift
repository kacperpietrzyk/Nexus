import Foundation
import NexusCore
import Observation
import SwiftData

/// Shared data feed for the Liquid Projects/Execution screen (Task 8, spec
/// `liquid_productivity_design_system/docs/07_MODULE_PROJECTS.md`). One
/// `@Observable` instance is owned by the app shell so the main column
/// (`LiquidProjectScreen`) and the right inspector (`ProjectInspector`) render
/// the same load — the identical sharing shape `LiquidTodayModel` uses.
///
/// Every feed is a REAL store read: live projects/sections/tasks via
/// `FetchDescriptor`, derived execution analytics via the pure
/// `ProjectExecutionModel` (Task 7), the canonical-note description through
/// `Project.canonicalNoteRef`, and project-scoped notes through the Link graph.
@MainActor
@Observable
public final class LiquidProjectsModel {

    /// Picker selection — `nil` shows the project list. Settable by the screen;
    /// the app layer reads it to decide whether the inspector slot mounts.
    public var selectedProjectID: UUID?

    // MARK: Picker feed

    /// Active top-level projects (same filter `ProjectsRootView` used: live,
    /// unarchived, no parent), sorted by name.
    public private(set) var projects: [Project] = []
    /// Open-task count per project for the picker rows.
    public private(set) var openCountsByProject: [UUID: Int] = [:]
    /// done/total completion per project for the picker rows.
    public private(set) var progressByProject: [UUID: Double] = [:]

    // MARK: Selected-project feed

    public private(set) var selectedProject: Project?
    /// Live tasks of the selected project, `orderIndex`-sorted (the same sort
    /// the existing `ProjectBoardView` query used, so lanes keep their order).
    public private(set) var tasks: [TaskItem] = []
    /// Live sections, `orderIndex`-sorted. Internal: `ProjectSection` is the
    /// module's internal `NexusCore.Section` alias, and no app-layer caller
    /// needs the raw sections.
    private(set) var sections: [ProjectSection] = []
    public private(set) var sectionNamesByID: [UUID: String] = [:]
    public private(set) var milestones: [ProjectExecutionModel.Milestone] = []
    public private(set) var progress: Double = 0
    public private(set) var health: ProjectExecutionModel.ProjectHealth = .onTrack
    public private(set) var risks: [ProjectExecutionModel.ProjectRisk] = []
    public private(set) var activity: [ProjectExecutionModel.ActivityEntry] = []
    /// First line of the project's canonical note (`canonicalNoteRef`) — the
    /// only real "description" the schema carries; `nil` → the header omits it.
    public private(set) var descriptionLine: String?
    /// Live comment count per task id (one grouped fetch) for the board cards.
    public private(set) var commentCountsByTask: [UUID: Int] = [:]
    /// Live subtask count per task id (one grouped fetch) for the board cards.
    public private(set) var subtaskCountsByTask: [UUID: Int] = [:]
    public private(set) var loadError: String?

    public init() {}

    /// Reloads the picker feed and (when a project is selected) every
    /// execution-screen feed. Synchronous main-actor store reads — the screen
    /// calls this from `.task` / `reloadOnStoreChange`, mirroring Today.
    public func reload(modelContext: ModelContext, now: Date = .now) {
        do {
            try loadProjects(modelContext: modelContext)
            try loadSelectedProject(modelContext: modelContext, now: now)
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    // MARK: - Picker

    private func loadProjects(modelContext: ModelContext) throws {
        let all = try modelContext.fetch(
            FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
        )
        projects = all.filter { $0.deletedAt == nil && $0.archivedAt == nil && $0.parentProjectID == nil }

        // One grouped fetch covers both picker columns (open count + progress).
        let projectTasks = try modelContext.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.deletedAt == nil && $0.projectID != nil })
        )
        let byProject = Dictionary(grouping: projectTasks, by: { $0.projectID })
        var openCounts: [UUID: Int] = [:]
        var progresses: [UUID: Double] = [:]
        for project in projects {
            let tasks = byProject[project.id] ?? []
            openCounts[project.id] = tasks.count(where: { $0.status == .open })
            progresses[project.id] = ProjectExecutionModel.progress(tasks: tasks)
        }
        openCountsByProject = openCounts
        progressByProject = progresses

        // A deleted/archived selection falls back to the picker list.
        if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }
    }

    // MARK: - Selected project

    private func loadSelectedProject(modelContext: ModelContext, now: Date) throws {
        guard let pid = selectedProjectID, let project = projects.first(where: { $0.id == pid }) else {
            selectedProject = nil
            tasks = []
            sections = []
            sectionNamesByID = [:]
            milestones = []
            progress = 0
            health = .onTrack
            risks = []
            activity = []
            descriptionLine = nil
            commentCountsByTask = [:]
            subtaskCountsByTask = [:]
            return
        }

        selectedProject = project
        tasks = try modelContext.fetch(
            FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.projectID == pid && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.orderIndex)]
            )
        )
        sections = try modelContext.fetch(
            FetchDescriptor<ProjectSection>(
                predicate: #Predicate { $0.projectID == pid && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.orderIndex)]
            )
        )
        sectionNamesByID = Dictionary(
            sections.map { ($0.id, $0.name) },
            uniquingKeysWith: { current, _ in current }
        )

        let tasksBySection = Dictionary(grouping: tasks.filter { $0.sectionID != nil }, by: { $0.sectionID ?? UUID() })
        milestones = ProjectExecutionModel.milestones(sections: sections, tasksBySection: tasksBySection)
        progress = ProjectExecutionModel.progress(tasks: tasks)
        health = ProjectExecutionModel.health(tasks: tasks, now: now)
        risks = ProjectExecutionModel.risks(tasks: tasks, now: now)

        let notes = try projectNotes(project: project, modelContext: modelContext)
        activity = ProjectExecutionModel.activity(tasks: tasks, notes: notes)
        descriptionLine = Self.firstLine(of: notes.first(where: { $0.id == project.canonicalNoteRef }))

        try loadCardCounts(modelContext: modelContext)
    }

    /// Notes that genuinely belong to the project: the canonical page plus
    /// notes connected through the Link graph in either direction — both
    /// already-indexed reads (the same seams `LiquidTodayModel` walks).
    private func projectNotes(project: Project, modelContext: ModelContext) throws -> [Note] {
        var noteIDs: Set<UUID> = []
        if let canonical = project.canonicalNoteRef {
            noteIDs.insert(canonical)
        }
        let linkRepository = LinkRepository(context: modelContext)
        for link in (try? linkRepository.outgoing(from: (.project, project.id))) ?? [] where link.toKind == .note {
            noteIDs.insert(link.toID)
        }
        for link in (try? linkRepository.backlinks(to: (.project, project.id))) ?? [] where link.fromKind == .note {
            noteIDs.insert(link.fromID)
        }
        guard !noteIDs.isEmpty else { return [] }
        let idArray = Array(noteIDs)
        return try modelContext.fetch(
            FetchDescriptor<Note>(predicate: #Predicate { idArray.contains($0.id) && $0.deletedAt == nil })
        )
    }

    /// Board-card metadata counts, fetched once per reload (never per card):
    /// live comments grouped by `itemID`, live subtasks grouped by parent.
    private func loadCardCounts(modelContext: ModelContext) throws {
        let taskIDs = Set(tasks.map(\.id))
        guard !taskIDs.isEmpty else {
            commentCountsByTask = [:]
            subtaskCountsByTask = [:]
            return
        }

        let idArray = Array(taskIDs)
        let comments = try modelContext.fetch(
            FetchDescriptor<Comment>(predicate: #Predicate { idArray.contains($0.itemID) && $0.deletedAt == nil })
        )
        commentCountsByTask = comments.reduce(into: [:]) { counts, comment in
            counts[comment.itemID, default: 0] += 1
        }

        // Project-scoped in-store. #Predicate can't unwrap optionals with
        // postfix `!`, and the `?? sentinel` nil-coalescing form fails SQL
        // generation at runtime ("unimplemented SQL generation … bad LHS" —
        // TERNARY is not a valid IN lhs). The `if let` membership form below
        // IS translatable — it's the same shape `SubtaskListView.progress`
        // already ships, and `LiquidProjectsModelTests` exercises this fetch
        // against a real store.
        let subtasks = try modelContext.fetch(
            FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    if let parentTaskID = task.parentTaskID {
                        task.deletedAt == nil && taskIDs.contains(parentTaskID)
                    } else {
                        false
                    }
                }
            )
        )
        subtaskCountsByTask = subtasks.reduce(into: [:]) { counts, subtask in
            guard let parent = subtask.parentTaskID else { return }
            counts[parent, default: 0] += 1
        }
    }

    /// First non-empty line of the canonical note's plain text, used as the
    /// header description. Internal static so the rule is unit-testable.
    static func firstLine(of note: Note?) -> String? {
        guard let note else { return nil }
        return note.plainText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
    }
}
