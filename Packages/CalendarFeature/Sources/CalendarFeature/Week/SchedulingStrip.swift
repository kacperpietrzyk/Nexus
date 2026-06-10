import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A schedulable task for the strip/inspector: open, no due date, and no live
/// `ScheduledBlock` yet — a plain value so the views stay store-free.
struct WeekUnscheduledTask: Identifiable, Equatable {
    let id: UUID
    let title: String
    let projectName: String?
    let estimatedSeconds: Int?
}

/// Loads the strip's Unscheduled Tasks from the REAL store: the same
/// `TodayQuery.noDate()` bucket the Today surfaces use, minus tasks that
/// already have a live `ScheduledBlock` (so a drop visibly moves the task out
/// of the strip), with project names resolved for the tag pills.
enum WeekUnscheduledLoader {
    @MainActor
    static func load(modelContext: ModelContext) -> [WeekUnscheduledTask] {
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let tasks =
            (try? TodayQuery().noDate(excludingProjectIDs: archivedProjectIDs).apply(in: modelContext)) ?? []

        let blockDescriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let scheduledTaskIDs = Set(((try? modelContext.fetch(blockDescriptor)) ?? []).map(\.taskID))

        let projectDescriptor = FetchDescriptor<Project>()
        let liveProjects = ((try? modelContext.fetch(projectDescriptor)) ?? [])
            .filter { $0.deletedAt == nil && $0.archivedAt == nil }
        let projectNamesByID = Dictionary(
            liveProjects.map { ($0.id, $0.name) },
            uniquingKeysWith: { current, _ in current }
        )

        return
            tasks
            .filter { !scheduledTaskIDs.contains($0.id) }
            .map { task in
                WeekUnscheduledTask(
                    id: task.id,
                    title: task.title,
                    projectName: task.projectID.flatMap { projectNamesByID[$0] },
                    estimatedSeconds: task.estimatedDurationSeconds
                )
            }
    }
}

/// Bottom scheduling strip (`docs/06_MODULE_CALENDAR.md` §Bottom scheduling
/// strip): three zones — draggable Unscheduled Tasks, the drop-zone panel, and
/// the Focus Time Recommendation card whose CTA schedules the top unscheduled
/// task into today's first free gap through the existing manual-block seam.
struct SchedulingStrip: View {

    let tasks: [WeekUnscheduledTask]
    /// First free ≥1 h gap left in today's workday (nil = none / today is not
    /// in the visible week).
    let focusGap: DateInterval?
    let onScheduleTopTask: (DateInterval) -> Void
    /// A task dropped on the middle zone opens the existing schedule
    /// affordance (`ManualBlockView`) pre-selected with that task.
    /// `@MainActor` so the async `NSItemProvider` load can hop back to the
    /// main actor with a `Sendable` closure (Swift 6).
    let onDropTaskToZone: @MainActor (UUID) -> Void
    let onAddTask: (() -> Void)?

    @State private var zoneTargeted = false

    /// Reference proportions (`references/02_calendar_week.png`): the strip
    /// rows stay compact under the grid; 4 rows ≈ the reference density.
    private static let maxVisibleTasks = 4

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            unscheduledCard
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            dropZoneCard
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            focusCard
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Zone 1: Unscheduled Tasks

    @ViewBuilder
    private var unscheduledCard: some View {
        LiquidGlassCard("Unscheduled Tasks") {
            if tasks.isEmpty {
                LiquidEmptyState(
                    systemImage: "tray",
                    message: "Every open task has a date or a scheduled block."
                ) {
                    if let onAddTask {
                        LiquidPrimaryButton("Add task", action: onAddTask)
                    }
                }
            } else {
                VStack(spacing: DS.Space.xxs) {
                    ForEach(tasks.prefix(Self.maxVisibleTasks)) { task in
                        taskRow(task)
                    }
                    if tasks.count > Self.maxVisibleTasks {
                        Text("+\(tasks.count - Self.maxVisibleTasks) more")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.s)
                    }
                }
            }
        } trailing: {
            if !tasks.isEmpty {
                Text("\(tasks.count)")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
    }

    private func taskRow(_ task: WeekUnscheduledTask) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
                .accessibilityHidden(true)
            Text(task.title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .lineLimit(1)
            if let projectName = task.projectName {
                LiquidPill(projectName, color: DS.ColorToken.accentCyan)
            }
            Spacer(minLength: DS.Space.s)
            if let seconds = task.estimatedSeconds, seconds > 0 {
                Text(WeekDurationText.text(for: TimeInterval(seconds)))
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
        .accessibilityLabel("Unscheduled task: \(task.title)")
    }

    // MARK: - Zone 2: Drop Zone

    private var dropZoneCard: some View {
        LiquidDropZone(
            systemImage: "calendar.badge.plus",
            title: "Drag tasks to time slots",
            isTargeted: zoneTargeted
        )
        .frame(maxHeight: .infinity)
        .onDrop(of: [.text], isTargeted: $zoneTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String, let taskID = UUID(uuidString: string) else { return }
                _Concurrency.Task { @MainActor in
                    onDropTaskToZone(taskID)
                }
            }
            return true
        }
    }

    // MARK: - Zone 3: Focus Time Recommendation

    @ViewBuilder
    private var focusCard: some View {
        LiquidGlassCard("Focus Time Recommendation") {
            if let gap = focusGap {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(
                        "\(WeekEventBlock.timeFormatter.string(from: gap.start)) – "
                            + WeekEventBlock.timeFormatter.string(from: gap.end)
                    )
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    // Real reason only: the gap is genuinely free in the loaded
                    // calendar — no fabricated "energy" rationale.
                    Text("Today's calendar is free here (\(WeekDurationText.text(for: gap.duration))).")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LiquidPrimaryButton("Schedule task here") { onScheduleTopTask(gap) }
                        .disabled(tasks.isEmpty)
                    if tasks.isEmpty {
                        Text("Add an unscheduled task to use this slot.")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                }
            } else {
                LiquidEmptyState(
                    systemImage: "moon.zzz",
                    message: "No free focus gaps left in today's workday."
                )
            }
        }
    }
}

/// Shared "1h 30m" duration formatting for the week surfaces.
enum WeekDurationText {
    static func text(for duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
