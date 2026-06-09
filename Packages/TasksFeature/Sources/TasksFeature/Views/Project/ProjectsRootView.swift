import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Top-level Projects destination for the Mac shell. Lists every active project
/// (with a prominent create CTA when empty) and, on selection, opens the full
/// `ProjectPageView` (header + lifecycle status + Linear-style board). This is
/// the discoverability surface: before this view, projects were only reachable
/// via the standalone-chrome sidebar that the embedded Mac shell never mounts,
/// so the user "couldn't find project management".
public struct ProjectsRootView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedProjectID: UUID?
    @State private var editorPresented = false
    @State private var error: String?

    private let onOpenTask: ((TaskItem) -> Void)?

    public init(onOpenTask: ((TaskItem) -> Void)? = nil) {
        self.onOpenTask = onOpenTask
    }

    private var activeProjects: [Project] {
        projects.filter { $0.deletedAt == nil && $0.archivedAt == nil && $0.parentProjectID == nil }
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return activeProjects.first { $0.id == selectedProjectID }
    }

    public var body: some View {
        Group {
            if let project = selectedProject {
                ProjectPageView(
                    project: project,
                    onSelectTask: onOpenTask,
                    onBack: { selectedProjectID = nil }
                )
            } else {
                projectList
            }
        }
        .sheet(isPresented: $editorPresented) {
            ProjectEditorSheet(project: nil)
        }
    }

    private var projectList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Projects")
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.primary)
                    Spacer()
                    NexusButton(
                        variant: .primary, size: .sm, action: { editorPresented = true },
                        label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("New Project")
                            }
                        }
                    )
                    .help("Create project")
                    .accessibilityLabel("Create project")
                }

                if activeProjects.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(activeProjects) { project in
                            ProjectListRow(project: project) {
                                selectedProjectID = project.id
                            }
                        }
                    }
                }

                if let error {
                    Text(error)
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.primary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(NexusColor.Text.disabled)
            Text("No projects yet")
                .nexusType(.body)
                .foregroundStyle(NexusColor.Text.secondary)
            Text("Group related tasks into a project and track them on a Linear-style board.")
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.tertiary)
                .frame(maxWidth: 360, alignment: .leading)
            NexusButton(
                variant: .primary, size: .md, action: { editorPresented = true },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Create your first project")
                    }
                }
            )
            .accessibilityLabel("Create your first project")
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectListRow: View {
    @Environment(\.modelContext) private var modelContext

    let project: Project
    let action: () -> Void

    @Query private var tasks: [TaskItem]

    init(project: Project, action: @escaping () -> Void) {
        self.project = project
        self.action = action
        let pid = project.id
        _tasks = Query(
            filter: #Predicate<TaskItem> { task in
                task.projectID == pid && task.deletedAt == nil
            }
        )
    }

    private var openCount: Int {
        let open = TaskStatus.open.rawValue
        return tasks.filter { $0.statusRaw == open }.count
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: nexusProjectGlyph(named: project.color))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(1)
                    Text(ProjectPageView.statusLabel(project.status))
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }

                Spacer(minLength: 8)

                Text("\(openCount) open")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.disabled)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                    .fill(NexusColor.Glass.surface1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .nexusRowHover()
        .accessibilityLabel(project.name)
    }
}
