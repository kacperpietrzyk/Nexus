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

/// True when the due chip's overdue red already represents the same "you're
/// late" fact a missed/today deadline would — so the deadline chip is
/// suppressed to avoid two red tokens for one fact. Due wins (the overdue due
/// chip stays the single red token). Pure + module-scope so the precedence is
/// unit-tested and cannot silently regress; formatter tone outputs are left
/// untouched (suppression lives in the row, not the formatter).
internal func suppressesDeadlineChip(
    due: DueChipFormatter.DueChipLabel,
    deadline: DeadlineBadgePresentation?
) -> Bool {
    // Suppress ONLY a *missed* deadline under an overdue due chip — that is the
    // single sanctioned redundancy (both say "you're late"; the overdue due
    // chip wins as the one red token). Key on the semantic `kind`, never on the
    // human-readable label or on `tone`: a "deadline TODAY" is also `.rose` but
    // is a distinct, MORE-urgent hard-deadline fact (e.g. due slipped 3 days
    // ago, deadline is today) and must stay visible. A neutral future deadline
    // is likewise a distinct signal and is never suppressed.
    guard let deadline, deadline.kind == .missed else { return false }
    if case .overdue = due { return true }
    return false
}

/// One row in `TaskListView`. Displays status glyph, title, due chip,
/// priority pill, tag chips, and recurrence icon. Uses `NexusUI`
/// primitives so styling stays consistent with the design system.
///
/// MP-2 (LabKit migration): checkbox replaced by `NexusStatusGlyph`;
/// Mac hover reveals `NexusRowQuickActions`; touch platforms keep a visible
/// trailing menu affordance for row actions. Accent/semantic hues removed.
public struct TaskRowView: View {

    @Bindable public var task: TaskItem
    public let now: Date
    public let depth: Int
    public let blockedCount: Int?
    public let subtaskProgress: SubtaskProgress?
    public let isSubtasksExpanded: Bool
    public let showsDefaultTaskAssistMenu: Bool
    public let onToggleSubtasks: (() -> Void)?
    public let onToggleDone: () -> Void
    public let onSnooze: (() -> Void)?

    public init(
        task: TaskItem,
        now: Date = .now,
        depth: Int = 0,
        blockedCount: Int? = nil,
        subtaskProgress: SubtaskProgress? = nil,
        isSubtasksExpanded: Bool = false,
        showsDefaultTaskAssistMenu: Bool = true,
        onToggleSubtasks: (() -> Void)? = nil,
        onToggleDone: @escaping () -> Void,
        onSnooze: (() -> Void)? = nil
    ) {
        self._task = Bindable(task)
        self.now = now
        self.depth = depth
        self.blockedCount = blockedCount
        self.subtaskProgress = subtaskProgress
        self.isSubtasksExpanded = isSubtasksExpanded
        self.showsDefaultTaskAssistMenu = showsDefaultTaskAssistMenu
        self.onToggleSubtasks = onToggleSubtasks
        self.onToggleDone = onToggleDone
        self.onSnooze = onSnooze
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
            now: now,
            depth: depth,
            blockedCount: blockedCount,
            subtaskProgress: subtaskProgress,
            isSubtasksExpanded: isSubtasksExpanded,
            onToggleSubtasks: onToggleSubtasks,
            onToggleDone: onToggleDone,
            onSnooze: onSnooze
        )
    }
}

// MARK: - RowBody (separates hover @State from the outer view)

/// Inner view that owns the hover `@State` so the outer `TaskRowView` stays
/// lightweight and the hover toggle is scoped correctly.
private struct RowBody: View {
    let task: TaskItem
    let now: Date
    let depth: Int
    let blockedCount: Int?
    let subtaskProgress: SubtaskProgress?
    let isSubtasksExpanded: Bool
    let onToggleSubtasks: (() -> Void)?
    let onToggleDone: () -> Void
    let onSnooze: (() -> Void)?

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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            disclosureControl
            // Leading status glyph — LabKit row anatomy: glyph → title → spacer → trailing meta.
            // Snoozed maps to `.inReview` (dashed ring); override the glyph's own
            // a11y label so VoiceOver announces the truth ("Snoozed"), not "In review".
            statusToggleButton
            if isCompact {
                compactCentralContent
            } else {
                // Dense single scan-line: title dominates, with the achromatic
                // ranked priority bars immediately after it (every level distinct).
                // The body line is dropped in the list — density over preview text
                // (Linear/Raycast idiom). All meta moves to the trailing cluster.
                HStack(spacing: 6) {
                    Text(task.title)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.primary)
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
            // matches LabRowView ZStack anatomy, no layout jump.
            trailingSlot
        }
        .padding(.leading, horizontalPadding + indentation)
        .padding(.trailing, horizontalPadding)
        .padding(.vertical, verticalPadding)
        // Audit #15: the row base is now flat (`rowBackground == .clear`) so
        // a single task no longer reads as a stray dark rounded rectangle.
        // The ZStack keeps the same stacking order (single `.background`;
        // chained `.background` is inside-out and would occlude) so the
        // hover lift still renders ABOVE the (now transparent) base.
        // Glass.surface1 (0.05) ≈ LabKit white.opacity(0.035).
        .background(
            ZStack {
                rowBackground
                RoundedRectangle(cornerRadius: NexusRadius.r2)
                    .fill(isHovering ? NexusColor.Background.controlHover : Color.clear)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(NexusColor.Line.hairline).frame(height: 1)
        }
        .draggable(TaskItemDropPayload(taskID: task.id)) {
            dragPreview
        }
        .animation(NexusMotion.standard, value: isHovering)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .nexusPressable()
    }

    // MARK: Leading status glyph

    private var statusToggleButton: some View {
        Button(action: onToggleDone) {
            statusGlyph
                .accessibilityHidden(true)
                .frame(width: statusVisualSize, height: statusVisualSize)
                .frame(width: statusHitSize, height: statusHitSize)
                .background(statusButtonBackground, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.status == .done ? "Reopen task" : "Mark task done")
        .accessibilityValue(taskStatusAccessibilityValue)
        .accessibilityHint("Updates the task completion status.")
    }

    @ViewBuilder
    private var statusGlyph: some View {
        let glyph = NexusStatusGlyph(taskNexusStatus(for: task.status))
        if task.status == .snoozed {
            // `.inReview` glyph's built-in label is "In review"; snoozed tasks
            // must announce "Snoozed" to be truthful for VoiceOver.
            glyph.accessibilityLabel("Snoozed")
        } else {
            glyph
        }
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
                .foregroundStyle(NexusColor.Text.tertiary)
                .frame(width: 30, height: 30)
                .background(NexusColor.Background.control, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
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

    private var horizontalPadding: CGFloat { depth == 0 ? 16 : 12 }
    private var verticalPadding: CGFloat {
        // Tightened for the dense single-line row (Linear/Raycast density).
        #if os(macOS)
        depth == 0 ? 7 : 6
        #else
        depth == 0 ? 9 : 8
        #endif
    }
    private var indentation: CGFloat { CGFloat(min(depth, 6)) * 20 }
    private var statusVisualSize: CGFloat { 18 }
    private var statusHitSize: CGFloat {
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
        NexusColor.Background.control
        #endif
    }

    private var taskStatusAccessibilityValue: String {
        switch task.status {
        case .open: return "Open"
        case .done: return "Done"
        case .snoozed: return "Snoozed"
        }
    }

    // Audit #15: flat by default (was depth-0 `Background.raised` /
    // subtask `Background.base` — an opaque per-row card that, with one
    // isolated task, looked like a stray dark rectangle). `.clear` lets
    // the page show through; the `.background` ZStack's hover overlay
    // (`Glass.surface1`) still supplies the raised lift on hover and the
    // bottom hairline keeps list structure. Applies wherever `TaskRowView`
    // renders (Tasks list / subtasks / embedded Today) — consistent.
    private var rowBackground: Color { .clear }

    @ViewBuilder
    private var disclosureControl: some View {
        if let subtaskProgress, subtaskProgress.total > 0, let onToggleSubtasks {
            Button(action: onToggleSubtasks) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.tertiary)
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
            .nexusType(.bodySmall)
            .foregroundStyle(NexusColor.Text.primary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
            .overlay {
                RoundedRectangle(cornerRadius: NexusRadius.r2)
                    .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
            }
    }

    // Right-aligned meta cluster, ordered quiet → loud (rightmost = strongest):
    // tags · overflow · recurrence · blocks · subtasks · deadline (only if not
    // suppressed by an overdue due chip) · DUE. The overdue due chip is the
    // single red urgency token and sits at the trailing edge where the eye
    // lands first on a right-aligned cluster.
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
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
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
        let hasTags = !task.tags.isEmpty
        let hasRecurrence = task.recurrenceRule != nil
        let hasBlocks = (blockedCount ?? 0) > 0
        let hasSubtasks = (subtaskProgress?.total ?? 0) > 0
        if hasTags || hasRecurrence || hasBlocks || hasSubtasks || showsDeadline {
            HStack(spacing: 6) {
                ForEach(Array(task.tags.prefix(3).enumerated()), id: \.offset) { _, tag in
                    NexusChip("#\(tag)")
                }
                if task.tags.count > 3 {
                    NexusChip("+\(task.tags.count - 3)")
                }
                if hasRecurrence {
                    Image(systemName: "repeat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
                if let blockedCount, blockedCount > 0 {
                    NexusChip("blocks \(blockedCount)", tone: .neutral)
                }
                if let subtaskProgress, subtaskProgress.total > 0 {
                    NexusChip(
                        subtaskProgress.label,
                        systemImage: "checklist",
                        tone: subtaskProgress.isComplete ? .positive : .neutral)
                }
                if let deadline, showsDeadline {
                    NexusChip(deadline.label, systemImage: deadline.systemImage, tone: deadline.tone)
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
            ForEach(Array(task.tags.prefix(3).enumerated()), id: \.offset) { _, tag in
                NexusChip("#\(tag)")
            }
            if task.tags.count > 3 {
                NexusChip("+\(task.tags.count - 3)")
            }
            if task.recurrenceRule != nil {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            if let blockedCount, blockedCount > 0 {
                NexusChip("blocks \(blockedCount)", tone: .neutral)
            }
            if let subtaskProgress, subtaskProgress.total > 0 {
                NexusChip(
                    subtaskProgress.label,
                    systemImage: "checklist",
                    tone: subtaskProgress.isComplete ? .positive : .neutral
                )
            }
            if let deadline, showsDeadline {
                NexusChip(deadline.label, systemImage: deadline.systemImage, tone: deadline.tone)
            }
            dueChipView(due)
        }
    }

    private static let chipCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    @ViewBuilder
    private func dueChipView(_ label: DueChipFormatter.DueChipLabel) -> some View {
        switch label {
        case .noDate:
            EmptyView()
        case .overdue(let daysLate):
            // The single red urgency token — restrained tinted-ink chip.
            NexusChip("\(daysLate)d late", systemImage: "exclamationmark.triangle.fill", tone: .rose)
        case .today(let timeOfDay):
            NexusChip(timeOfDay.map { "Today \($0)" } ?? "Today", systemImage: "calendar")
        case .tomorrow(let timeOfDay):
            NexusChip(timeOfDay.map { "Tomorrow \($0)" } ?? "Tomorrow", systemImage: "calendar")
        case .future(let date, let timeOfDay):
            let label = timeOfDay.map { "\(date) \($0)" } ?? date
            NexusChip(label, systemImage: "calendar")
        }
    }

    // Priority is ranked on a non-color channel (red is spent on the temporal
    // axis). The shipped achromatic `NexusPriorityBars` ranks EVERY level
    // (low = 1 / medium = 2 / high = 3 filled bars, with a weight ramp and the
    // single lime accent reserved for the urgent crest); no-priority tasks omit
    // it. This restores the P2/P3 distinction the dense list had dropped — the
    // brief's rule is "rank, don't strip" — by reusing the purpose-built
    // primitive rather than re-inventing a P1-only glyph.
    @ViewBuilder
    private var priorityIndicator: some View {
        if let level = priorityLevel {
            NexusPriorityBars(level)
        }
    }

    private var priorityLevel: NexusPriorityLevel? {
        switch task.priority {
        case .none: return nil
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
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
    .background(NexusColor.Background.base)
    .padding(40)
}
