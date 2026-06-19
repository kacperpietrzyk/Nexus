import NexusCore
import NexusUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct TaskItemDropPayload: Codable, Hashable, Sendable, Transferable {
    public let taskID: UUID

    public init(taskID: UUID) {
        self.taskID = taskID
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .nexusTaskItemID)
    }
}

extension UTType {
    static let nexusTaskItemID = UTType(exportedAs: "com.kacperpietrzyk.nexus.task-item-id")
}

// MARK: - Status mapping (testable seam — module-scope, not @MainActor)

/// Maps a `TaskStatus` to the achromatic `NexusStatus` glyph state.
/// Exhaustive switch — no `default` so adding a new `TaskStatus` case is a compile error.
internal func taskNexusStatus(for status: TaskStatus) -> NexusStatus {
    switch status {
    case .open: return .todo
    case .done: return .done
    case .snoozed: return .inReview
    }
}

/// True when a missed deadline chip should be suppressed because an overdue
/// due chip already represents the same "you're late" fact (due wins).
internal func suppressesDeadlineChip(
    due: DueChipFormatter.DueChipLabel,
    deadline: DeadlineBadgePresentation?
) -> Bool {
    // Key on `.missed` kind, not on tone — a "deadline TODAY" is also `.rose`
    // but is a distinct more-urgent fact and must not be suppressed.
    guard let deadline, deadline.kind == .missed else { return false }
    if case .overdue = due { return true }
    return false
}

/// Pure seam for the row's project pill — unit-testable at module scope.
internal enum TaskRowProjectPill {
    /// Returns the label to render, or nil to omit the pill.
    static func label(for projectName: String?) -> String? {
        guard let name = projectName, !name.isEmpty else { return nil }
        return name
    }
}

/// One row in `TaskListView`: Liquid checkbox, title, priority pill, project
/// pill, tag pills, and trailing due/deadline metadata. Mac hover reveals
/// `NexusRowQuickActions`; touch platforms show a visible trailing menu.
public struct TaskRowView: View {

    @Bindable public var task: TaskItem
    public let projectName: String?
    public let now: Date
    public let depth: Int
    public let blockedCount: Int?
    public let subtaskProgress: SubtaskProgress?
    public let isSubtasksExpanded: Bool
    public let showsDefaultTaskAssistMenu: Bool
    public let onToggleSubtasks: (() -> Void)?
    public let onToggleDone: () -> Void
    public let onSnooze: (() -> Void)?
    /// Multi-select state (driven by the surface's `SelectionModel`). While
    /// `isSelecting`, the leading status checkbox cross-fades to a selection
    /// checkmark and stops capturing taps, so the row's own tap toggles
    /// selection instead of completing the task.
    public let isSelecting: Bool
    public let isSelected: Bool

    public init(
        task: TaskItem,
        projectName: String? = nil,
        now: Date = .now,
        depth: Int = 0,
        blockedCount: Int? = nil,
        subtaskProgress: SubtaskProgress? = nil,
        isSubtasksExpanded: Bool = false,
        showsDefaultTaskAssistMenu: Bool = true,
        onToggleSubtasks: (() -> Void)? = nil,
        onToggleDone: @escaping () -> Void,
        onSnooze: (() -> Void)? = nil,
        isSelecting: Bool = false,
        isSelected: Bool = false
    ) {
        self._task = Bindable(task)
        self.projectName = projectName
        self.now = now
        self.depth = depth
        self.blockedCount = blockedCount
        self.subtaskProgress = subtaskProgress
        self.isSubtasksExpanded = isSubtasksExpanded
        self.showsDefaultTaskAssistMenu = showsDefaultTaskAssistMenu
        self.onToggleSubtasks = onToggleSubtasks
        self.onToggleDone = onToggleDone
        self.onSnooze = onSnooze
        self.isSelecting = isSelecting
        self.isSelected = isSelected
    }

    public var body: some View {
        if showsDefaultTaskAssistMenu {
            rowContent.taskAssistContextMenu(for: task)
        } else {
            rowContent
        }
    }

    // MARK: - Row layout

    private var rowContent: some View {
        RowBody(
            task: task,
            projectName: projectName,
            now: now,
            depth: depth,
            blockedCount: blockedCount,
            subtaskProgress: subtaskProgress,
            isSubtasksExpanded: isSubtasksExpanded,
            onToggleSubtasks: onToggleSubtasks,
            onToggleDone: onToggleDone,
            onSnooze: onSnooze,
            isSelecting: isSelecting,
            isSelected: isSelected
        )
    }
}

// MARK: - RowBody (separates hover @State from the outer view)

/// Inner view that owns the hover `@State` so the outer `TaskRowView` stays
/// lightweight and the hover toggle is scoped correctly.
private struct RowBody: View {
    let task: TaskItem
    let projectName: String?
    let now: Date
    let depth: Int
    let blockedCount: Int?
    let subtaskProgress: SubtaskProgress?
    let isSubtasksExpanded: Bool
    let onToggleSubtasks: (() -> Void)?
    let onToggleDone: () -> Void
    let onSnooze: (() -> Void)?
    let isSelecting: Bool
    let isSelected: Bool

    @State private var isHovering = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Compact width (iPhone, narrow split) can't hold the dense single scan-line
    /// — title + priority + a full meta cluster + the trailing menu overflow a
    /// ~360pt row, starving the title to nothing. There the row goes two-line:
    /// title (+ the single loud due token) on top, the quieter meta below.
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    /// Row hover wash — same calibration as NexusUI's LiquidListKit rows
    /// (09_SWIFTUI_IMPLEMENTATION_GUIDE §Hover: subtle fill, no scale in
    /// dense lists); the constant is private there so it is mirrored here.
    private static let hoverWash = Color.white.opacity(0.04)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            disclosureControl
            // Leading Liquid checkbox — row anatomy: checkbox → title → spacer
            // → trailing meta. Snoozed renders a dashed ring; the button's a11y
            // value announces the truth ("Snoozed"). In multi-select mode the
            // checkbox cross-fades to a selection checkmark (`leadingSlot`).
            leadingSlot
            if isCompact {
                compactCentralContent
            } else {
                // Dense single scan-line: title dominates, with the priority
                // pill immediately after it. The body line is dropped in the
                // list — density over preview text. All meta moves to the
                // trailing cluster.
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(DS.FontToken.body)
                        .strikethrough(task.status == .done)
                        .foregroundStyle(
                            task.status == .done ? DS.ColorToken.textTertiary : DS.ColorToken.textPrimary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    priorityIndicator
                }
                // The title owns the flexible width: when the row can't fit title +
                // meta on one line, the title truncates with an ellipsis rather than
                // ceding its width to the (now fixed-size) meta chips.
                .layoutPriority(1)
                Spacer(minLength: 8)
                // Right-aligned meta cluster (quiet → loud, overdue red rightmost),
                // then the trailing slot (mac hover actions / touch menu).
                metaCluster
            }
            // Trailing slot: resting meta fades out, hover cluster fades in —
            // no layout jump.
            trailingSlot
        }
        .padding(.leading, horizontalPadding + indentation)
        .padding(.trailing, horizontalPadding)
        .padding(.vertical, verticalPadding)
        // Flat base + a subtle hover wash on glass: the row never paints an
        // opaque slab over the shell panel; hover lift is a translucent white
        // fill per the Liquid list idiom.
        .background(
            ZStack {
                rowBackground
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(isHovering ? Self.hoverWash : Color.clear)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.ColorToken.strokeHairline).frame(height: 1)
        }
        .draggable(TaskItemDropPayload(taskID: task.id)) {
            dragPreview
        }
        .animation(DS.Motion.hover, value: isHovering)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .nexusPressable()
    }

    // MARK: Leading Liquid checkbox

    /// Leading slot: the status checkbox and a multi-select checkmark are BOTH
    /// always in the view tree (constant structure — a conditional swap would
    /// re-diff the row mid-flight and crash the List), cross-faded by opacity.
    /// While selecting, the checkbox stops capturing taps so the row's own tap
    /// routes to the selection toggle.
    private var leadingSlot: some View {
        ZStack {
            statusToggleButton
                .opacity(isSelecting ? 0 : 1)
                .allowsHitTesting(!isSelecting)
            SelectionCheckmark(isSelected: isSelected)
                .frame(width: statusHitSize, height: statusHitSize)
                .opacity(isSelecting ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private var statusToggleButton: some View {
        Button(action: onToggleDone) {
            LiquidTaskCheckbox(state: liquidCheckboxState(for: task.status), isHovering: isHovering)
                .accessibilityHidden(true)
                .frame(width: statusHitSize, height: statusHitSize)
                .background(statusButtonBackground, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.status == .done ? "Reopen task" : "Mark task done")
        .accessibilityValue(taskStatusAccessibilityValue)
        .accessibilityHint("Updates the task completion status.")
    }

    // MARK: Trailing slot (ZStack — resting vs hover, LabRowView pattern)

    @ViewBuilder
    private var trailingSlot: some View {
        #if os(macOS)
        ZStack(alignment: .trailing) {
            // Resting state: invisible on hover so quick actions can overlay
            Color.clear
                .frame(width: 1, height: 1)
                .opacity(isHovering ? 0 : 1)

            // Hover state: quick-action cluster slides in from the right.
            // macOS-only — touch platforms get the visible menu below.
            quickActionsCluster
                .opacity(isHovering ? 1 : 0)
                .scaleEffect(isHovering ? 1 : 0.9)
                .offset(x: isHovering ? 0 : 6)
        }
        #else
        if onSnooze != nil {
            visibleActionsMenu
        }
        #endif
    }

    #if os(macOS)
    private var quickActionsCluster: some View {
        var actions: [NexusRowQuickAction] = [
            NexusRowQuickAction(
                icon: task.status == .done ? "arrow.uturn.backward" : "checkmark",
                accessibilityLabel: task.status == .done ? "Reopen task" : "Mark task done",
                action: onToggleDone)
        ]
        if let onSnooze {
            actions.append(
                NexusRowQuickAction(
                    icon: "clock", accessibilityLabel: "Snooze", action: onSnooze))
        }
        return NexusRowQuickActions(actions: actions)
    }
    #endif

    #if !os(macOS)
    private var visibleActionsMenu: some View {
        Menu {
            Button {
                onToggleDone()
            } label: {
                Label(task.status == .done ? "Reopen" : "Mark done", systemImage: "checkmark.circle")
            }
            if let onSnooze {
                Button {
                    onSnooze()
                } label: {
                    Label("Snooze 1h", systemImage: "clock")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.ColorToken.textTertiary)
                .frame(width: 30, height: 30)
                .background(DS.ColorToken.glassSoft, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(DS.ColorToken.strokeDefault, lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Task actions")
        .accessibilityHint("Shows available actions for this task.")
    }
    #endif

    // MARK: Helpers

    private var horizontalPadding: CGFloat { depth == 0 ? DS.Space.l : DS.Space.m }
    private var verticalPadding: CGFloat {
        // Tightened for the dense single-line row (Linear/Raycast density).
        #if os(macOS)
        depth == 0 ? 7 : 6
        #else
        depth == 0 ? 9 : 8
        #endif
    }
    private var indentation: CGFloat { CGFloat(min(depth, 6)) * DS.Space.xl }
    private var statusHitSize: CGFloat {
        // 01_FOUNDATIONS §Dostępność: ≥28 pt targets on macOS; 44 pt on touch.
        #if os(macOS)
        28
        #else
        44
        #endif
    }

    private var statusButtonBackground: Color {
        #if os(macOS)
        .clear
        #else
        DS.ColorToken.glassSoft
        #endif
    }

    private var taskStatusAccessibilityValue: String {
        switch task.status {
        case .open: return "Open"
        case .done: return "Done"
        case .snoozed: return "Snoozed"
        }
    }

    // Flat by default: `.clear` lets the glass panel show through; the hover
    // wash supplies the lift and the bottom hairline keeps list structure.
    // Applies wherever `TaskRowView` renders (Tasks list / subtasks /
    // embedded Today) — consistent.
    private var rowBackground: Color { .clear }

    @ViewBuilder
    private var disclosureControl: some View {
        if let subtaskProgress, subtaskProgress.total > 0, let onToggleSubtasks {
            Button(action: onToggleSubtasks) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(width: 18, height: 18)
                    .rotationEffect(isSubtasksExpanded ? .degrees(90) : .zero)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSubtasksExpanded ? "Collapse subtasks" : "Expand subtasks")
        } else {
            Color.clear
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }

    private var dragPreview: some View {
        Text(task.title)
            .font(DS.FontToken.body)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .background(
                DS.ColorToken.glassStrong,
                in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .strokeBorder(DS.ColorToken.strokeDefault, lineWidth: 1)
            }
    }

    // MARK: Compact (two-line) central content

    /// iPhone/compact layout: the title (with priority + the single loud due
    /// token) takes the first line; tags and the quieter meta drop to a second
    /// line where they have the full row width and never crush the title.
    @ViewBuilder
    private var compactCentralContent: some View {
        let due = DueChipFormatter.label(for: task, now: now, calendar: Self.chipCalendar)
        let deadline = DeadlineBadgeFormatter.presentation(
            deadlineAt: task.deadlineAt, now: now, calendar: Self.chipCalendar)
        let showsDeadline = deadline != nil && !suppressesDeadlineChip(due: due, deadline: deadline)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(task.title)
                    .font(DS.FontToken.body)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(
                        task.status == .done ? DS.ColorToken.textTertiary : DS.ColorToken.textPrimary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                priorityIndicator
                Spacer(minLength: 6)
                dueChipView(due)
            }
            compactSecondaryMeta(showsDeadline: showsDeadline, deadline: deadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compactSecondaryMeta(
        showsDeadline: Bool,
        deadline: DeadlineBadgePresentation?
    ) -> some View {
        let hasProject = TaskRowProjectPill.label(for: projectName) != nil
        let hasTags = !task.tags.isEmpty
        let hasRecurrence = task.recurrenceRule != nil
        let hasBlocks = (blockedCount ?? 0) > 0
        let hasSubtasks = (subtaskProgress?.total ?? 0) > 0
        if hasProject || hasTags || hasRecurrence || hasBlocks || hasSubtasks || showsDeadline {
            HStack(spacing: 6) {
                projectPill
                tagPills
                if hasRecurrence {
                    recurrenceGlyph
                }
                if let blockedCount, blockedCount > 0 {
                    LiquidPill("blocks \(blockedCount)", color: DS.ColorToken.statusNeutral)
                }
                subtaskPill
                if let deadline, showsDeadline {
                    LiquidPill(deadline.label, color: TaskRowLiquidStyle.pillColor(for: deadline.tone))
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var metaCluster: some View {
        let due = DueChipFormatter.label(for: task, now: now, calendar: Self.chipCalendar)
        let deadline = DeadlineBadgeFormatter.presentation(
            deadlineAt: task.deadlineAt,
            now: now,
            calendar: Self.chipCalendar
        )
        let showsDeadline = deadline != nil && !suppressesDeadlineChip(due: due, deadline: deadline)
        HStack(spacing: 6) {
            projectPill
            tagPills
            if task.recurrenceRule != nil {
                recurrenceGlyph
            }
            if let blockedCount, blockedCount > 0 {
                LiquidPill("blocks \(blockedCount)", color: DS.ColorToken.statusNeutral)
            }
            subtaskPill
            if let deadline, showsDeadline {
                LiquidPill(deadline.label, color: TaskRowLiquidStyle.pillColor(for: deadline.tone))
            }
            dueChipView(due)
        }
    }

    @ViewBuilder
    private var projectPill: some View {
        if let label = TaskRowProjectPill.label(for: projectName) {
            LiquidPill(label, color: DS.ColorToken.statusNeutral)
        }
    }

    /// Tag pills with deterministic quiet accents, capped at 2 + a real "+N".
    @ViewBuilder
    private var tagPills: some View {
        let split = TaskRowLiquidStyle.visibleTags(task.tags)
        // `id: \.offset` — user tags may repeat; offsets are unique.
        ForEach(Array(split.visible.enumerated()), id: \.offset) { _, tag in
            LiquidPill(tag, color: TaskRowLiquidStyle.tagAccent(for: tag))
        }
        if split.overflow > 0 {
            LiquidPill("+\(split.overflow)", color: DS.ColorToken.statusNeutral)
        }
    }

    @ViewBuilder
    private var subtaskPill: some View {
        if let subtaskProgress, subtaskProgress.total > 0 {
            LiquidPill(
                subtaskProgress.label,
                color: subtaskProgress.isComplete
                    ? DS.ColorToken.statusSuccess : DS.ColorToken.statusNeutral
            )
        }
    }

    private var recurrenceGlyph: some View {
        Image(systemName: "repeat")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.ColorToken.textTertiary)
            .accessibilityLabel("Repeats")
    }

    private static let chipCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    /// Trailing due metadata — plain right-aligned text per the reference
    /// rows. Overdue is the single red token (semibold); today reads in
    /// accent blue; everything later stays tertiary ink.
    @ViewBuilder
    private func dueChipView(_ label: DueChipFormatter.DueChipLabel) -> some View {
        if let due = TaskRowLiquidStyle.dueMetadata(for: label) {
            Text(due.text)
                .font(due.role == .overdue ? DS.FontToken.metadata.weight(.semibold) : DS.FontToken.metadata)
                .monospacedDigit()
                .foregroundStyle(TaskRowLiquidStyle.dueColor(for: due.role))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Priority pill in the design system's priority colors (03_COMPONENTS.md
    /// §Pills / Tags: high = red, medium = amber, low = blue via
    /// `TopPrioritiesCard.color(for:)` — one hue source for list + Today card).
    /// No-priority rows omit it.
    @ViewBuilder
    private var priorityIndicator: some View {
        if let label = TaskRowLiquidStyle.priorityLabel(for: task.priority) {
            LiquidPill(label, color: TopPrioritiesCard.color(for: task.priority))
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TaskRowView(
            task: TaskItem(title: "Reply Magda", dueAt: .now, priority: .high, tags: ["email", "work"]),
            onToggleDone: {}
        )
        TaskRowView(
            task: TaskItem(title: "Buy groceries", priority: .none, tags: ["shopping"]),
            onToggleDone: {}
        )
    }
    .padding(40)
    .background(DS.ColorToken.backgroundApp)
}
