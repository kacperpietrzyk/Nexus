import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Picker list cap width — same readable column the old `ProjectsRootView`
/// list used (no spec value; the execution screen itself is full-width).
private let pickerMaxWidth: CGFloat = 720

/// Tabs (spec §Tabs). Three focused, non-duplicating surfaces ship:
/// Overview (dashboard — stats + milestones + health/risk/activity),
/// Board (full Kanban), and List (full task table). The mockup's
/// Timeline/Files/Notes/Settings tabs have no backing surface and Notes
/// would require a cross-feature import (NotesFeature) the architecture
/// forbids — all intentionally omitted, no dead tabs.
enum ProjectScreenTab: String, CaseIterable, Identifiable {
    case overview
    case board
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .board: return "Board"
        case .list: return "List"
        }
    }
}

enum ProjectsPickerMode: String, CaseIterable, Identifiable {
    case grid
    case roadmap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .roadmap: return "Roadmap"
        }
    }
}

/// The Liquid Projects / Execution main column (Task 8, spec
/// `docs/07_MODULE_PROJECTS.md`): project picker list → per-project execution
/// screen (header + tabs + milestones + Kanban + all-tasks table). All tabs
/// render full-width; health/risk/activity content lives in the Overview tab
/// (`ProjectOverview`). Both screen and overview read the same shared
/// `LiquidProjectsModel` — the `LiquidTodayScreen` sharing shape.
///
/// Picker UX keeps the old `ProjectsRootView` selection shape (list →
/// full-page project, breadcrumb back) restyled liquid; selection state lives
/// on the shared model so the app layer can show the correct tab content.
public struct LiquidProjectScreen: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    private let model: LiquidProjectsModel
    private let onOpenTask: (TaskItem) -> Void

    @State private var tab: ProjectScreenTab = .overview
    @State private var pickerMode: ProjectsPickerMode = .grid
    @State private var editorPresented = false
    @State private var editingProject: Project?

    public init(model: LiquidProjectsModel, onOpenTask: @escaping (TaskItem) -> Void) {
        self.model = model
        self.onOpenTask = onOpenTask
    }

    public var body: some View {
        Group {
            if LiquidReferenceMode.isEnabled {
                referenceExecutionScreen(LiquidProjectsReferenceData.snapshot(now: .now))
            } else if let project = model.selectedProject {
                executionScreen(project)
            } else if model.projects.isEmpty {
                emptyStore
            } else {
                pickerList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { reload() }
        .reloadOnStoreChange { reload() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            reload()
        }
        // Same create/edit seam the old root view used; reload on dismiss so
        // a just-created project appears without waiting for the next save
        // notification cycle.
        .sheet(
            isPresented: $editorPresented,
            onDismiss: { reload() },
            content: { ProjectEditorSheet(project: nil) }
        )
        .sheet(
            item: $editingProject,
            onDismiss: { reload() },
            content: { project in ProjectEditorSheet(project: project) }
        )
    }

    private func reload() {
        model.reload(modelContext: modelContext)
    }

    // MARK: - Empty store

    private var emptyStore: some View {
        LiquidEmptyState(
            systemImage: "square.stack.3d.up",
            message: "No projects yet — group related tasks and track them on a board."
        ) {
            LiquidPrimaryButton("Create your first project", systemImage: "plus") {
                editorPresented = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Picker list

    private var pickerList: some View {
        ScrollView {
            Group {
                switch pickerMode {
                case .grid:
                    pickerGridMode
                        .frame(maxWidth: pickerMaxWidth, alignment: .topLeading)
                case .roadmap:
                    pickerRoadmapMode
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var pickerGridMode: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            pickerHeader
            pickerLoadError
            pickerGrid
        }
    }

    private var pickerRoadmapMode: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            pickerHeader
            pickerLoadError
            ProjectRoadmap(
                bars: model.roadmapBars,
                cycles: model.roadmapCycles,
                now: .now,
                calendar: .current,
                onSelectProject: { projectID in
                    guard let project = model.projects.first(where: { $0.id == projectID }) else { return }
                    select(project)
                }
            )
        }
    }

    private var pickerHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DS.Space.m) {
                pickerTitle
                Spacer(minLength: DS.Space.m)
                pickerControls
            }

            VStack(alignment: .leading, spacing: DS.Space.s) {
                pickerTitle
                pickerControls
            }
        }
    }

    private var pickerTitle: some View {
        Text("Projects")
            .font(DS.FontToken.displayMedium)
            .foregroundStyle(DS.ColorToken.textPrimary)
    }

    private var pickerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s) {
                pickerModeControl
                pickerNewProjectButton
            }

            VStack(alignment: .leading, spacing: DS.Space.s) {
                pickerModeControl
                pickerNewProjectButton
            }
        }
    }

    private var pickerModeControl: some View {
        LiquidSegmentedControl(
            options: ProjectsPickerMode.allCases.map { .init($0, label: $0.label) },
            selection: $pickerMode
        )
    }

    private var pickerNewProjectButton: some View {
        LiquidPrimaryButton("New Project", systemImage: "plus") {
            editorPresented = true
        }
    }

    @ViewBuilder
    private var pickerLoadError: some View {
        if let error = model.loadError {
            Text(error)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.statusDanger)
        }
    }

    private var pickerGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: DS.Space.m)],
            alignment: .leading,
            spacing: DS.Space.m
        ) {
            ForEach(model.projects) { project in
                ProjectPickerRow(
                    project: project,
                    openCount: model.openCountsByProject[project.id] ?? 0,
                    progress: model.progressByProject[project.id] ?? 0
                ) {
                    select(project)
                }
            }
        }
    }

    private func select(_ project: Project?) {
        withAnimation(DS.Motion.selection) {
            model.selectedProjectID = project?.id
            tab = .overview
        }
        reload()
    }

    // MARK: - Execution screen

    private func executionScreen(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                ProjectHeader(
                    project: project,
                    descriptionLine: model.descriptionLine,
                    progress: model.progress,
                    onBack: { select(nil) },
                    onEdit: { editingProject = project }
                )

                if let error = model.loadError {
                    Text(error)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.statusDanger)
                }

                LiquidSegmentedControl(
                    options: ProjectScreenTab.allCases.map { .init($0, label: $0.label) },
                    selection: $tab
                )

                switch tab {
                case .overview:
                    ProjectOverview(model: model, onOpenTask: onOpenTask)
                case .board:
                    board(project)
                case .list:
                    table
                }
            }
            .padding(DS.Space.l)
        }
    }

    private func referenceExecutionScreen(_ snapshot: LiquidProjectsReferenceData.Snapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                ProjectHeader(
                    project: snapshot.project,
                    descriptionLine: snapshot.descriptionLine,
                    progress: snapshot.progress,
                    onBack: {},
                    onEdit: {}
                )

                LiquidSegmentedControl(
                    options: ProjectScreenTab.allCases.map { .init($0, label: $0.label) },
                    selection: $tab
                )

                switch tab {
                case .overview:
                    ProjectOverview(model: model, onOpenTask: onOpenTask)
                case .board:
                    ProjectKanban(
                        projectID: snapshot.project.id,
                        tasks: snapshot.tasks,
                        sectionNames: snapshot.sectionNamesByID,
                        commentCounts: snapshot.commentCountsByTask,
                        subtaskCounts: snapshot.subtaskCountsByTask,
                        onSelect: onOpenTask,
                        onChanged: {}
                    )
                case .list:
                    ProjectTaskTable(
                        tasks: snapshot.tasks,
                        sectionNames: snapshot.sectionNamesByID,
                        now: .now,
                        onSelect: onOpenTask
                    )
                }
            }
            .padding(DS.Space.l)
        }
    }

    private func board(_ project: Project) -> some View {
        ProjectKanban(
            projectID: project.id,
            tasks: model.tasks,
            sectionNames: model.sectionNamesByID,
            commentCounts: model.commentCountsByTask,
            subtaskCounts: model.subtaskCountsByTask,
            onSelect: onOpenTask,
            onChanged: { reload() }
        )
    }

    private var table: some View {
        ProjectTaskTable(
            tasks: model.tasks,
            sectionNames: model.sectionNamesByID,
            now: .now,
            onSelect: onOpenTask
        )
    }
}

// MARK: - Picker row

private struct ProjectPickerRow: View {
    let project: Project
    let openCount: Int
    let progress: Double
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: nexusProjectGlyph(named: project.color))
                        // 14 pt identity glyph, same scale the old root-view
                        // rows used; no DS icon-size token.
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)

                    Text(project.name)
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: DS.Space.s)

                    Image(systemName: "chevron.right")
                        // 10 pt disclosure chevron; no DS icon-size token.
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textMuted)
                        .accessibilityHidden(true)
                }

                Text(ProjectFormatters.statusLabel(project.status))
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)

                HStack(spacing: DS.Space.s) {
                    LiquidProgressLine(value: progress)
                        .accessibilityHidden(true)

                    Text("\(openCount) open")
                        .font(DS.FontToken.metadata.monospacedDigit())
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .fixedSize()
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .liquidGlass(.card, radius: DS.Radius.l, isHovering: hovering)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
        .accessibilityLabel("\(project.name), \(openCount) open tasks")
    }
}
