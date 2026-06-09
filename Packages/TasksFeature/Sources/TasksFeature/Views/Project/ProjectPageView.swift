import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Full project page: a header (name + glyph + lifecycle `ProjectStatus` menu +
/// section summary) over the `ProjectBoardView` Kanban board. This surfaces
/// `ProjectStatus`, which is modeled but never previously shown in the UI, and
/// makes the status editable through `ProjectRepository.setStatus`.
///
/// The project's `canonicalNoteRef` page is NOT rendered inline: rendering a
/// `Note` would require importing `NotesFeature` into `TasksFeature`, which the
/// architecture forbids (feature modules never cross-import). When a page exists
/// the header shows a non-rendering "linked page" affordance instead; deep
/// rendering is a deferred follow-up.
struct ProjectPageView: View {
    @Environment(\.modelContext) private var modelContext

    let project: Project
    let onSelectTask: ((TaskItem) -> Void)?
    let onBack: (() -> Void)?

    @Query private var sections: [ProjectSection]
    @State private var error: String?

    init(project: Project, onSelectTask: ((TaskItem) -> Void)? = nil, onBack: (() -> Void)? = nil) {
        self.project = project
        self.onSelectTask = onSelectTask
        self.onBack = onBack
        let pid = project.id
        _sections = Query(
            filter: #Predicate<ProjectSection> { section in
                section.projectID == pid && section.deletedAt == nil
            },
            sort: \ProjectSection.orderIndex
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().overlay(NexusColor.Line.hairline)

            ProjectBoardView(projectID: project.id, onSelect: onSelectTask)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let onBack {
                    NexusButton(variant: .ghost, size: .iconSm, action: onBack) {
                        Image(systemName: "chevron.left")
                    }
                    .help("All projects")
                    .accessibilityLabel("All projects")
                }

                Image(systemName: nexusProjectGlyph(named: project.color))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.secondary)

                Text(project.name)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                statusMenu
            }

            HStack(spacing: 12) {
                Text("\(sections.count) section\(sections.count == 1 ? "" : "s")")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)

                if project.canonicalNoteRef != nil {
                    Label("Linked page", systemImage: "doc.text")
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .labelStyle(.titleAndIcon)
                }

                if let error {
                    Text(error)
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(ProjectStatus.allCases, id: \.self) { status in
                Button {
                    setStatus(status)
                } label: {
                    if status == project.status {
                        Label(Self.statusLabel(status), systemImage: "checkmark")
                    } else {
                        Text(Self.statusLabel(status))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(NexusColor.Text.tertiary)
                    .frame(width: 6, height: 6)
                Text(Self.statusLabel(project.status))
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(NexusColor.Background.control, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Project status: \(Self.statusLabel(project.status))")
    }

    @MainActor
    private func setStatus(_ status: ProjectStatus) {
        guard status != project.status else { return }
        do {
            try ProjectRepository(context: modelContext).setStatus(status, on: project)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    static func statusLabel(_ status: ProjectStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .planned: return "Planned"
        case .active: return "Active"
        case .inReview: return "In Review"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}
