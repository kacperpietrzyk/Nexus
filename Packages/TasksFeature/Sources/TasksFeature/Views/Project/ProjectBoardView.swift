import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Linear-style Kanban board for a single project: one column per `WorkflowState`
/// (plus a leading "No Status" lane for project tasks that have not opted into
/// the workflow machine). Each card is a task; dragging a card between columns
/// updates that task's `workflowState` through the single sanctioned write path
/// `TaskItemRepository.setWorkflowState` (spec §5.3 — never a raw status write).
///
/// Cards are grouped into columns by `projectBoardColumns` (the pure, unit-tested
/// bucketing seam). Sections are surfaced as a card prefix rather than a second
/// axis — keeping the board flat-per-project keeps the columns readable; the
/// section name rides along on each card.
struct ProjectBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    let projectID: UUID
    let onSelect: ((TaskItem) -> Void)?

    @Query private var tasks: [TaskItem]
    @Query private var sections: [ProjectSection]
    @State private var error: String?

    init(projectID: UUID, onSelect: ((TaskItem) -> Void)? = nil) {
        self.projectID = projectID
        self.onSelect = onSelect
        let pid = projectID
        _tasks = Query(
            filter: #Predicate<TaskItem> { task in
                task.projectID == pid && task.deletedAt == nil
            },
            sort: \TaskItem.orderIndex
        )
        _sections = Query(
            filter: #Predicate<ProjectSection> { section in
                section.projectID == pid && section.deletedAt == nil
            },
            sort: \ProjectSection.orderIndex
        )
    }

    private var columns: [ProjectBoardColumn] {
        projectBoardColumns(for: tasks)
    }

    private var sectionNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.name) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { column in
                        ProjectBoardColumnView(
                            column: column,
                            sectionNames: sectionNames,
                            onSelect: onSelect,
                            onDrop: { payloads in handleDrop(payloads, into: column.state) }
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private func handleDrop(_ payloads: [TaskItemDropPayload], into state: WorkflowState?) -> Bool {
        // The "No Status" lane is the home for nil-workflow project tasks; we do
        // not actively demote a task back to nil from the board (no raw clearer
        // on the sanctioned path), so a drop there is a no-op success.
        guard let state else { return true }
        guard let repository else {
            error = "Task repository is unavailable."
            return false
        }

        let ids = Set(payloads.map(\.taskID))
        let movable = tasks.filter { ids.contains($0.id) && $0.workflowState != state }
        guard !movable.isEmpty else { return true }

        do {
            for task in movable {
                try repository.setWorkflowState(state, on: task)
            }
            error = nil
            return true
        } catch {
            self.error = String(describing: error)
            return false
        }
    }
}

// MARK: - Column

private struct ProjectBoardColumnView: View {
    let column: ProjectBoardColumn
    let sectionNames: [UUID: String]
    let onSelect: ((TaskItem) -> Void)?
    let onDrop: @MainActor ([TaskItemDropPayload]) -> Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            VStack(alignment: .leading, spacing: 8) {
                ForEach(column.tasks) { task in
                    ProjectBoardCard(
                        task: task,
                        sectionName: task.sectionID.flatMap { sectionNames[$0] },
                        onSelect: onSelect
                    )
                }
                if column.tasks.isEmpty {
                    emptyDropHint
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 260, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                .fill(isTargeted ? NexusColor.Background.controlHover : NexusColor.Glass.surface1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                .strokeBorder(
                    isTargeted ? NexusColor.Line.regular : NexusColor.Line.hairline,
                    lineWidth: 1
                )
        }
        .dropDestination(for: TaskItemDropPayload.self) { payloads, _ in
            onDrop(payloads)
        } isTargeted: {
            isTargeted = $0
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(column.title.uppercased())
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)
            Text("\(column.tasks.count)")
                .font(NexusType.metaMono)
                .monospacedDigit()
                .foregroundStyle(NexusColor.Text.disabled)
            Spacer(minLength: 0)
        }
    }

    private var emptyDropHint: some View {
        RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
            .strokeBorder(NexusColor.Line.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 40)
            .overlay {
                Text("Drop here")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.disabled)
            }
    }
}

// MARK: - Card

private struct ProjectBoardCard: View {
    let task: TaskItem
    let sectionName: String?
    let onSelect: ((TaskItem) -> Void)?

    var body: some View {
        Button {
            onSelect?(task)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let sectionName {
                    Text(sectionName.uppercased())
                        .nexusType(.eyebrow)
                        .foregroundStyle(NexusColor.Text.disabled)
                        .lineLimit(1)
                }

                Text(task.title)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                metadataRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                    .fill(NexusColor.Background.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .nexusRowHover()
        .draggable(TaskItemDropPayload(taskID: task.id)) {
            Text(task.title)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
                .padding(8)
                .background(NexusColor.Background.controlHover, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
        }
        .accessibilityLabel(task.title)
    }

    @ViewBuilder
    private var metadataRow: some View {
        let due = task.dueAt
        let agent = task.agent
        if due != nil || agent != nil {
            HStack(spacing: 8) {
                if let due {
                    Label(Self.dueFormatter.string(from: due), systemImage: "calendar")
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
                if let agent {
                    Label(agentLabel(agent), systemImage: "person")
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
                Spacer(minLength: 0)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private func agentLabel(_ agent: AgentAssignee) -> String {
        switch agent {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
