import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Picker list cap width — same readable column the old `ProjectsRootView`
/// list used (no spec value; the execution screen itself is full-width).
private let pickerMaxWidth: CGFloat = 720
/// Mini progress line width on a picker row.
private let pickerProgressWidth: CGFloat = 90

/// Tabs (spec §Tabs). Only surfaces that really exist ship: Overview (the
/// milestones + board + table scroll) and List (the table full-height). The
/// mockup's Timeline/Milestones/Files/Settings tabs have no backing surface
/// and Notes would require a cross-feature import (NotesFeature) the
/// architecture forbids — all intentionally omitted, no dead tabs.
enum ProjectScreenTab: String, CaseIterable, Identifiable {
    case overview
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .list: return "List"
        }
    }
}

/// The Liquid Projects / Execution main column (Task 8, spec
/// `docs/07_MODULE_PROJECTS.md`): project picker list → per-project execution
/// screen (header + tabs + milestones + Kanban + all-tasks table). The
/// matching right inspector (`ProjectInspector`) is mounted separately
/// through the app shell's inspector slot; both read the same shared
/// `LiquidProjectsModel` — the `LiquidTodayScreen` sharing shape.
///
/// Picker UX keeps the old `ProjectsRootView` selection shape (list →
/// full-page project, breadcrumb back) restyled liquid; selection state lives
/// on the shared model so the app layer can gate the inspector slot.
public struct LiquidProjectScreen: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    private let model: LiquidProjectsModel
    private let onOpenTask: (TaskItem) -> Void

    @State private var tab: ProjectScreenTab = .overview
    @State private var editorPresented = false
    @State private var editingProject: Project?

    public init(model: LiquidProjectsModel, onOpenTask: @escaping (TaskItem) -> Void) {
        self.model = model
        self.onOpenTask = onOpenTask
    }

    public var body: some View {
        Group {
            if let project = model.selectedProject {
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
            message: "No projects yet. Group related tasks into a project and track them on a board."
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
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack {
                    Text("Projects")
                        .font(DS.FontToken.displayMedium)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    LiquidPrimaryButton("New Project", systemImage: "plus") {
                        editorPresented = true
                    }
                }

                if let error = model.loadError {
                    Text(error)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.statusDanger)
                }

                VStack(spacing: DS.Space.s) {
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
            .padding(DS.Space.l)
            .frame(maxWidth: pickerMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    MilestoneStrip(milestones: model.milestones)
                    board(project)
                    table
                case .list:
                    table
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
            HStack(spacing: DS.Space.m) {
                Image(systemName: nexusProjectGlyph(named: project.color))
                    // 14 pt identity glyph on a 48 pt row, same scale the old
                    // root-view rows used; no DS icon-size token.
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)
                    Text(ProjectPageView.statusLabel(project.status))
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }

                Spacer(minLength: DS.Space.s)

                LiquidProgressLine(value: progress)
                    .frame(width: pickerProgressWidth)
                    .accessibilityHidden(true)

                Text("\(openCount) open")
                    .font(DS.FontToken.metadata.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textTertiary)

                Image(systemName: "chevron.right")
                    // 10 pt disclosure chevron; no DS icon-size token.
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Space.m)
            .frame(height: 48)
            .contentShape(Rectangle())
            .liquidGlass(.card, radius: DS.Radius.m, isHovering: hovering)
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
