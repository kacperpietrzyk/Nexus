import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct ProjectsSidebarSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var taskRepository

    @Query(sort: \Project.name) private var queriedProjects: [Project]
    @Query(sort: \ProjectSection.orderIndex) private var queriedSections: [ProjectSection]

    @Binding private var selection: TaskFilter
    private let onSelect: () -> Void

    @State private var editorProject: ProjectEditorMode?
    @State private var sectionDraft: SectionDraft?
    @State private var error: String?
    @State private var archivedExpanded = false

    public init(selection: Binding<TaskFilter>, onSelect: @escaping () -> Void = {}) {
        self._selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if projects.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(projects) { project in
                        projectBlock(project)
                    }
                }
            }

            if !archivedProjects.isEmpty {
                archivedSection
            }

            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(2)
            }
        }
        .sheet(item: $editorProject) { mode in
            ProjectEditorSheet(project: mode.project)
        }
        .alert(sectionDraft?.title ?? "Section", isPresented: sectionAlertBinding) {
            TextField("Name", text: sectionNameBinding)
            Button("Cancel", role: .cancel) { sectionDraft = nil }
            Button(sectionDraft?.buttonTitle ?? "Save") { saveSectionDraft() }
        }
    }

    private var projects: [Project] {
        queriedProjects.filter {
            $0.deletedAt == nil && $0.archivedAt == nil && $0.parentProjectID == nil
        }
    }

    /// Top-level archived projects (recoverable). Mirrors `projects` but with the
    /// archived predicate flipped — archived children surface only via their
    /// archived root being restored (unarchive is non-cascading by design).
    private var archivedProjects: [Project] {
        queriedProjects.filter {
            $0.deletedAt == nil && $0.archivedAt != nil && $0.parentProjectID == nil
        }
    }

    /// Collapsible "Archived" group so archived projects are viewable/recoverable
    /// from the sidebar without being mistaken for active ones. Archived rows do
    /// NOT drive `selection` (every task surface filters archived projects out via
    /// `archivedProjectIDs()`, so selecting one would land on an empty list); the
    /// row's only affordance is the "Unarchive Project" context action.
    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                archivedExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: archivedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Archived")
                        .nexusType(.eyebrow)
                    Text("\(archivedProjects.count)")
                        .nexusType(.caption)
                    Spacer()
                }
                .foregroundStyle(NexusColor.Text.muted)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nexusRowHover()
            .accessibilityLabel("Archived projects")

            if archivedExpanded {
                ForEach(archivedProjects) { project in
                    ProjectSidebarRow(
                        title: project.name,
                        systemImage: nexusProjectGlyph(named: project.color),
                        isSelected: false,
                        isDropTargeted: false,
                        depth: 0,
                        action: {}
                    )
                    .contextMenu {
                        Button("Unarchive Project") { unarchive(project) }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Projects")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            Spacer()

            NexusButton(
                variant: .ghost, size: .iconSm, action: { editorProject = .create },
                label: {
                    Image(systemName: "plus")
                }
            )
            .help("Create project")
            .accessibilityLabel("Create project")
        }
    }

    private var emptyState: some View {
        Button {
            editorProject = .create
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                Text("Add project")
                Spacer()
            }
            .nexusType(.bodySmall)
            .foregroundStyle(NexusColor.Text.tertiary)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .nexusRowHover()
    }

    private func projectBlock(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            dropTarget(projectID: project.id, sectionID: nil) { isTargeted in
                ProjectSidebarRow(
                    title: project.name,
                    systemImage: nexusProjectGlyph(named: project.color),
                    isSelected: selection == .project(project.id),
                    isDropTargeted: isTargeted,
                    depth: 0,
                    action: {
                        selection = .project(project.id)
                        onSelect()
                    }
                )
                .contextMenu {
                    Button("New Section") { sectionDraft = .create(projectID: project.id) }
                    Button("Edit Project") { editorProject = .edit(project) }
                    Divider()
                    Button("Archive Project", role: .destructive) { archive(project) }
                }
            }

            ForEach(sections(for: project)) { section in
                dropTarget(projectID: project.id, sectionID: section.id) { isTargeted in
                    ProjectSidebarRow(
                        title: section.name,
                        systemImage: "rectangle.split.3x1",
                        isSelected: selection == .projectSection(project.id, section.id),
                        isDropTargeted: isTargeted,
                        depth: 1,
                        action: {
                            selection = .projectSection(project.id, section.id)
                            onSelect()
                        }
                    )
                    .contextMenu {
                        Button("Rename Section") { sectionDraft = .rename(section) }
                        Button("Delete Section", role: .destructive) { delete(section) }
                    }
                }
            }
        }
    }

    private func sections(for project: Project) -> [ProjectSection] {
        queriedSections.filter { $0.projectID == project.id && $0.deletedAt == nil }
    }

    private func dropTarget<Content: View>(
        projectID: UUID,
        sectionID: UUID?,
        @ViewBuilder content: @escaping (Bool) -> Content
    ) -> some View {
        ProjectDropTarget(
            projectID: projectID,
            sectionID: sectionID,
            assign: assignDroppedTasks,
            content: content
        )
    }

    @MainActor
    private func assignDroppedTasks(
        _ payloads: [TaskItemDropPayload],
        projectID: UUID,
        sectionID: UUID?
    ) -> Bool {
        guard let taskRepository else {
            error = "Task repository is unavailable."
            return false
        }

        do {
            _ = try ProjectSidebarAssignment.assign(
                payloads: payloads,
                projectID: projectID,
                sectionID: sectionID,
                modelContext: modelContext,
                repository: taskRepository
            )
            error = nil
            return true
        } catch {
            self.error = String(describing: error)
            return false
        }
    }

    @MainActor
    private func archive(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).archive(project)
            selection = selection.replacingArchivedProject(project.id)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func unarchive(_ project: Project) {
        do {
            try ProjectRepository(context: modelContext).unarchive(project)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func delete(_ section: ProjectSection) {
        do {
            try SectionRepository(context: modelContext).delete(section)
            if selection == .projectSection(section.projectID, section.id) {
                selection = .project(section.projectID)
            }
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func saveSectionDraft() {
        guard let draft = sectionDraft else { return }
        let cleanedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        do {
            let repository = SectionRepository(context: modelContext)
            switch draft.mode {
            case .create(let projectID):
                try repository.create(projectID: projectID, name: cleanedName)
            case .rename(let section):
                try repository.rename(section, to: cleanedName)
            }
            sectionDraft = nil
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private var sectionAlertBinding: Binding<Bool> {
        Binding(
            get: { sectionDraft != nil },
            set: { if !$0 { sectionDraft = nil } }
        )
    }

    private var sectionNameBinding: Binding<String> {
        Binding(
            get: { sectionDraft?.name ?? "" },
            set: { sectionDraft?.name = $0 }
        )
    }
}

private struct ProjectDropTarget<Content: View>: View {
    let projectID: UUID
    let sectionID: UUID?
    let assign: @MainActor ([TaskItemDropPayload], UUID, UUID?) -> Bool
    @ViewBuilder let content: (Bool) -> Content

    @State private var isTargeted = false

    var body: some View {
        content(isTargeted)
            .dropDestination(for: TaskItemDropPayload.self) { payloads, _ in
                assign(payloads, projectID, sectionID)
            } isTargeted: {
                isTargeted = $0
            }
    }
}

private struct ProjectSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDropTargeted: Bool
    let depth: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                    .frame(width: 16)

                Text(title)
                    .nexusType(.bodySmall)
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(rowBackground, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
            .overlay {
                RoundedRectangle(cornerRadius: NexusRadius.r2)
                    .strokeBorder(rowBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .nexusRowHover()
        .accessibilityLabel(title)
    }

    private var rowBackground: Color {
        if isDropTargeted {
            return NexusColor.Background.controlHover
        }
        if isSelected {
            return NexusColor.Background.controlHover
        }
        return .clear
    }

    private var rowBorder: Color {
        if isDropTargeted {
            return NexusColor.Line.regular
        }
        if isSelected {
            return NexusColor.Line.regular
        }
        return .clear
    }
}

private enum ProjectEditorMode: Identifiable {
    case create
    case edit(Project)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let project):
            return project.id.uuidString
        }
    }

    var project: Project? {
        switch self {
        case .create:
            return nil
        case .edit(let project):
            return project
        }
    }
}

private struct SectionDraft: Identifiable {
    enum Mode {
        case create(projectID: UUID)
        case rename(ProjectSection)
    }

    let id = UUID()
    var mode: Mode
    var name: String

    static func create(projectID: UUID) -> SectionDraft {
        SectionDraft(mode: .create(projectID: projectID), name: "")
    }

    static func rename(_ section: ProjectSection) -> SectionDraft {
        SectionDraft(mode: .rename(section), name: section.name)
    }

    var title: String {
        switch mode {
        case .create:
            return "New Section"
        case .rename:
            return "Rename Section"
        }
    }

    var buttonTitle: String {
        switch mode {
        case .create:
            return "Create"
        case .rename:
            return "Save"
        }
    }
}
