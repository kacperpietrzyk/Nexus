import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Kanban column width — matches the existing `ProjectBoardView` lanes so the
/// board density carries over (no spec pt value; reference shows ~4 columns).
private let kanbanColumnWidth: CGFloat = 260
/// Lane tint opacities — spec §Visual rules: "Kanban columns should have
/// subtle tinted backgrounds, not solid colors". Fill below the LiquidPill
/// passive tint (14%), stroke matched to it.
private let laneFillOpacity = 0.06
private let laneStrokeOpacity = 0.14

/// Measures the lane HStack's intrinsic width so the board can show a
/// trailing-fade overflow cue when the columns exceed the viewport.
private struct BoardContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The liquid Kanban board (spec §Kanban board) labeled "Board" — NOT
/// "Active Sprint": there is no sprint backend, so no sprint header/range/
/// dropdown is fabricated. Columns reuse the existing board's pure grouping
/// (`projectBoardColumns`) and drag-move semantics (the single sanctioned
/// write path `TaskItemRepository.setWorkflowState`), so drags keep
/// persisting exactly as before. Cards carry real fields only: title,
/// priority pill, due date, comment/subtask counts — no issue keys (the
/// model has no short id) and no avatars (single-user app).
struct ProjectKanban: View {
    @Environment(\.taskRepository) private var repository

    let projectID: UUID
    let tasks: [TaskItem]
    let sectionNames: [UUID: String]
    let commentCounts: [UUID: Int]
    let subtaskCounts: [UUID: Int]
    let onSelect: (TaskItem) -> Void
    let onChanged: () -> Void

    @State private var error: String?
    /// Trailing-fade affordance: the board's six fixed-width lanes overflow any
    /// non-ultrawide window, so a "there's more →" cue and visible scroll
    /// indicator make the horizontal scroll discoverable (it always worked, it
    /// just read as non-scrollable without an affordance).
    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    private var hasOverflow: Bool { contentWidth > viewportWidth + 1 }

    private var columns: [ProjectBoardColumn] {
        projectBoardColumns(for: tasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Text("Board")
                    .font(DS.FontToken.section)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text("\(tasks.count) task\(tasks.count == 1 ? "" : "s")")
                    .font(DS.FontToken.metadata.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textTertiary)
                Spacer(minLength: 0)
            }

            if let error {
                Text(error)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.statusDanger)
                    .lineLimit(2)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    ForEach(columns) { column in
                        KanbanColumnView(
                            column: column,
                            projectID: projectID,
                            sectionNames: sectionNames,
                            commentCounts: commentCounts,
                            subtaskCounts: subtaskCounts,
                            onSelect: onSelect,
                            onDrop: { payloads in handleDrop(payloads, into: column.state) },
                            onCreate: { title in createTask(title, in: column.state) }
                        )
                    }
                }
                .padding(.bottom, DS.Space.xs)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: BoardContentWidthKey.self, value: proxy.size.width)
                    }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in viewportWidth = width }
                }
            }
            .onPreferenceChange(BoardContentWidthKey.self) { contentWidth = $0 }
            .overlay(alignment: .trailing) {
                if hasOverflow {
                    LinearGradient(
                        colors: [DS.ColorToken.backgroundApp.opacity(0), DS.ColorToken.backgroundApp.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Mutations (existing repository seams only)

    /// Identical move semantics to the legacy `ProjectBoardView.handleDrop`:
    /// nil-lane drops are a no-op success (no sanctioned workflow clearer),
    /// everything else routes through `setWorkflowState`.
    @MainActor
    private func handleDrop(_ payloads: [TaskItemDropPayload], into state: WorkflowState?) -> Bool {
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
            onChanged()
            return true
        } catch {
            self.error = String(describing: error)
            return false
        }
    }

    /// Add-task row seam (spec §Kanban "add task row"): the EXISTING creation
    /// path — `TaskItemRepository.insert` for the project task, then the
    /// sanctioned `setWorkflowState` write to land it in the lane (nil lane =
    /// plain project task, exactly what the "No Status" lane means).
    @MainActor
    private func createTask(_ title: String, in state: WorkflowState?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let repository else {
            error = "Task repository is unavailable."
            return
        }
        do {
            let task = TaskItem(title: trimmed, projectID: projectID)
            try repository.insert(task)
            if let state {
                try repository.setWorkflowState(state, on: task)
            }
            error = nil
            onChanged()
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - Column

private struct KanbanColumnView: View {
    let column: ProjectBoardColumn
    let projectID: UUID
    let sectionNames: [UUID: String]
    let commentCounts: [UUID: Int]
    let subtaskCounts: [UUID: Int]
    let onSelect: (TaskItem) -> Void
    let onDrop: @MainActor ([TaskItemDropPayload]) -> Bool
    let onCreate: (String) -> Void

    @State private var isTargeted = false
    @State private var isAdding = false
    @State private var draftTitle = ""
    @FocusState private var draftFocused: Bool

    /// Lane accent by workflow state — drives the subtle tint + header dot
    /// (spec: To Do blue, In Progress amber, In Review purple, Done green;
    /// queue/closure lanes stay neutral).
    private var accent: Color {
        switch column.state {
        case .todo: return DS.ColorToken.accentBlue
        case .inProgress: return DS.ColorToken.accentAmber
        case .inReview: return DS.ColorToken.accentPurple
        case .done: return DS.ColorToken.accentGreen
        case nil, .backlog, .canceled, .duplicate: return DS.ColorToken.statusNeutral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            header

            ForEach(column.tasks) { task in
                KanbanCard(
                    task: task,
                    sectionName: task.sectionID.flatMap { sectionNames[$0] },
                    commentCount: commentCounts[task.id] ?? 0,
                    subtaskCount: subtaskCounts[task.id] ?? 0,
                    onSelect: onSelect
                )
            }

            if column.tasks.isEmpty {
                LiquidDropZone(systemImage: "tray", title: "Drop here", isTargeted: isTargeted)
            }

            addRow
        }
        .padding(DS.Space.s)
        .frame(width: kanbanColumnWidth, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.ColorToken.glassSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(accent.opacity(isTargeted ? laneFillOpacity * 2 : laneFillOpacity))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .stroke(
                    isTargeted ? DS.ColorToken.accentPrimary : accent.opacity(laneStrokeOpacity),
                    lineWidth: 1
                )
        }
        .dropDestination(for: TaskItemDropPayload.self) { payloads, _ in
            onDrop(payloads)
        } isTargeted: {
            isTargeted = $0
        }
        .animation(DS.Motion.hover, value: isTargeted)
    }

    private var header: some View {
        HStack(spacing: DS.Space.xs) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(column.title)
                .font(DS.FontToken.bodyStrong)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Text("\(column.tasks.count)")
                .font(DS.FontToken.caption.monospacedDigit())
                .foregroundStyle(DS.ColorToken.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.xxs)
    }

    @ViewBuilder
    private var addRow: some View {
        if isAdding {
            TextField("Task title…", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .focused($draftFocused)
                .padding(DS.Space.s)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(DS.ColorToken.backgroundSunken.opacity(0.6))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
                }
                .onSubmit {
                    onCreate(draftTitle)
                    draftTitle = ""
                    isAdding = false
                }
                .kanbanDraftExitCommand {
                    draftTitle = ""
                    isAdding = false
                }
        } else {
            Button {
                isAdding = true
                draftFocused = true
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "plus")
                        // 10 pt plus matches the metadata line height; no DS icon token.
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add task")
                        .font(DS.FontToken.metadata)
                }
                .foregroundStyle(DS.ColorToken.textTertiary)
                .padding(.horizontal, DS.Space.s)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task to \(column.title)")
        }
    }
}

extension View {
    /// Escape cancels the add-task draft; `onExitCommand` is macOS/tvOS-only
    /// API (same guard shape as `FocusView.nexusFocusExitCommand`).
    @ViewBuilder
    fileprivate func kanbanDraftExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS) || os(tvOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }
}

// MARK: - Card

private struct KanbanCard: View {
    let task: TaskItem
    let sectionName: String?
    let commentCount: Int
    let subtaskCount: Int
    let onSelect: (TaskItem) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            onSelect(task)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let sectionName {
                    Text(sectionName.uppercased())
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textMuted)
                        .lineLimit(1)
                }

                Text(task.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                metadataRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s)
            .liquidGlass(.card, radius: DS.Radius.s, isHovering: hovering)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
        .draggable(TaskItemDropPayload(taskID: task.id)) {
            Text(task.title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .padding(DS.Space.s)
                .background(
                    DS.ColorToken.glassStrong,
                    in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                )
        }
        .accessibilityLabel(task.title)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: DS.Space.s) {
            if task.priority != .none {
                LiquidPill(
                    TopPrioritiesCard.label(for: task.priority),
                    color: TopPrioritiesCard.color(for: task.priority)
                )
            }

            if let due = task.dueAt {
                Label(ProjectFormatters.monthDay.string(from: due), systemImage: "calendar")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            if subtaskCount > 0 {
                Label("\(subtaskCount)", systemImage: "checklist")
                    .font(DS.FontToken.caption.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("\(subtaskCount) subtasks")
            }
            if commentCount > 0 {
                Label("\(commentCount)", systemImage: "bubble.left")
                    .font(DS.FontToken.caption.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("\(commentCount) comments")
            }
        }
    }
}
