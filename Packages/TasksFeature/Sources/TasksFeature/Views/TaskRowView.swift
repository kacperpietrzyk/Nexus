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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            disclosureControl
            // Leading status glyph — LabKit row anatomy: glyph → title → spacer → trailing meta.
            // Snoozed maps to `.inReview` (dashed ring); override the glyph's own
            // a11y label so VoiceOver announces the truth ("Snoozed"), not "In review".
            statusToggleButton
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
                if !task.body.isEmpty {
                    Text(task.body)
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(1)
                }
                metaStrip
            }
            Spacer(minLength: 12)
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
                    .fill(isHovering ? NexusColor.Glass.surface1 : Color.clear)
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
                .background(NexusColor.Glass.surface1.opacity(0.55), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(NexusColor.Line.hairline.opacity(0.7), lineWidth: 1)
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
        #if os(macOS)
        depth == 0 ? 10 : 8
        #else
        depth == 0 ? 12 : 10
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
        NexusColor.Glass.surface1
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

    @ViewBuilder
    private var metaStrip: some View {
        HStack(spacing: 6) {
            dueChip
            deadlineChip
            priorityPill
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
                // MP-2 accent burn-down: blocks chip → .neutral
                NexusChip("blocks \(blockedCount)", tone: .neutral)
            }
            if let subtaskProgress, subtaskProgress.total > 0 {
                NexusChip(
                    subtaskProgress.label,
                    systemImage: "checklist",
                    tone: subtaskProgress.isComplete ? .positive : .neutral
                )
            }
        }
    }

    @ViewBuilder
    private var deadlineChip: some View {
        if let presentation = DeadlineBadgeFormatter.presentation(
            deadlineAt: task.deadlineAt,
            now: now,
            calendar: Self.chipCalendar
        ) {
            NexusChip(
                presentation.label,
                systemImage: presentation.systemImage,
                tone: presentation.tone
            )
        }
    }

    private static let chipCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    @ViewBuilder
    private var dueChip: some View {
        switch DueChipFormatter.label(for: task, now: now, calendar: Self.chipCalendar) {
        case .noDate:
            EmptyView()
        case .overdue(let daysLate):
            NexusChip("\(daysLate)d late", systemImage: "exclamationmark.triangle.fill", tone: .rose)
        case .today(let timeOfDay):
            // MP-2 accent burn-down: temporal signal carried by label, achromatic
            NexusChip(timeOfDay.map { "Today \($0)" } ?? "Today", systemImage: "calendar")
        case .tomorrow(let timeOfDay):
            NexusChip(timeOfDay.map { "Tomorrow \($0)" } ?? "Tomorrow", systemImage: "calendar")
        case .future(let date, let timeOfDay):
            let label = timeOfDay.map { "\(date) \($0)" } ?? date
            NexusChip(label, systemImage: "calendar")
        }
    }

    @ViewBuilder
    private var priorityPill: some View {
        switch task.priority {
        case .high:
            // MP-2 accent burn-down: P1 chip → .neutral
            NexusChip("P1", systemImage: "exclamationmark", tone: .neutral)
        case .medium:
            NexusChip("P2")
        case .low:
            NexusChip("P3")
        case .none:
            EmptyView()
        }
    }
}

// MARK: - DeadlineBadgePresentation

public struct DeadlineBadgePresentation: Equatable, Sendable {
    public let label: String
    public let systemImage: String
    public let tone: NexusChipTone

    public init(label: String, systemImage: String = "flag.fill", tone: NexusChipTone) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
    }
}

// MARK: - DeadlineBadgeFormatter

public enum DeadlineBadgeFormatter {
    public static func presentation(
        deadlineAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> DeadlineBadgePresentation? {
        guard let deadlineAt else { return nil }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDeadline = calendar.startOfDay(for: deadlineAt)
        let dayDelta = calendar.dateComponents([.day], from: startOfToday, to: startOfDeadline).day ?? 0

        if dayDelta < 0 {
            return DeadlineBadgePresentation(label: "deadline missed", tone: .rose)
        }
        if dayDelta == 0 {
            return DeadlineBadgePresentation(label: "deadline today", tone: .rose)
        }

        // MP-2 accent burn-down: always .neutral regardless of 1…3 day window
        return DeadlineBadgePresentation(label: "deadline in \(dayDelta)d", tone: .neutral)
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
