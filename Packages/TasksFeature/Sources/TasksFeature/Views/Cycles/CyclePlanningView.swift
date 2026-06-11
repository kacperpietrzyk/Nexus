import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Cycle planning sheet (Tranche 2 Plan C, spec §4.2/§5): assign open backlog
/// tasks to the cycle, review completion stats, and act on the end-of-cycle
/// prompt. Cycles NEVER move work automatically (invariant I-C1): the single
/// "move open tasks & complete" button below is the only rollover path, and it
/// is a user action that calls `assignCycle` per task + `setStatus(.completed)`.
public struct CyclePlanningView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    let cycle: Cycle
    private let now: Date

    @State private var tasksInCycle: [TaskItem] = []
    @State private var backlog: [TaskItem] = []
    @State private var nextCycle: Cycle?
    @State private var error: String?

    public init(cycle: Cycle, now: Date = .now) {
        self.cycle = cycle
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            CycleStatsHeader(stats: stats)

            if let prompt {
                endOfCycleBanner(prompt)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    listSection(
                        "IN THIS CYCLE",
                        tasks: tasksInCycle,
                        emptyText: "No tasks assigned yet.",
                        actionTitle: "Remove",
                        action: { task in assign(task, to: nil) }
                    )
                    listSection(
                        "BACKLOG",
                        tasks: backlog,
                        emptyText: "No unassigned open tasks.",
                        actionTitle: "Add",
                        action: { task in assign(task, to: cycle.id) }
                    )
                }
            }
            .scrollIndicators(.hidden)

            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(2)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 560)
        .background(NexusColor.Background.panel)
        .task { reload() }
    }

    // MARK: - Derived

    private var stats: CycleStatsModel.Stats {
        CycleStatsModel.stats(tasks: tasksInCycle, cycleStartAt: cycle.startAt)
    }

    private var openInCycle: [TaskItem] {
        tasksInCycle.filter { $0.status != .done }
    }

    private var prompt: CycleStatsModel.EndOfCyclePrompt? {
        // Defensive: never offer this cycle as its own move target.
        let target = nextCycle?.id == cycle.id ? nil : nextCycle
        return CycleStatsModel.endOfCyclePrompt(
            status: cycle.status,
            endAt: cycle.endAt,
            now: now,
            openCount: openInCycle.count,
            nextCycleID: target?.id,
            nextCycleName: target?.name
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cycle.name)
                    .font(NexusType.h2)
                    .foregroundStyle(NexusColor.Text.primary)
                Text(subtitle)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            Spacer(minLength: 8)

            Button(
                action: { dismiss() },
                label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
            )
            .buttonStyle(.plain)
            .foregroundStyle(NexusColor.Text.tertiary)
            .background(NexusColor.Background.control.opacity(0.6), in: Circle())
            .overlay(Circle().stroke(NexusColor.Line.hairline, lineWidth: 1))
            .accessibilityLabel("Close cycle planner")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var subtitle: String {
        let range =
            "\(cycle.startAt.formatted(date: .abbreviated, time: .omitted)) – "
            + cycle.endAt.formatted(date: .abbreviated, time: .omitted)
        return "\(range) · \(statusLabel)"
    }

    private var statusLabel: String {
        switch cycle.status {
        case .upcoming: return "Upcoming"
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }

    private func endOfCycleBanner(_ prompt: CycleStatsModel.EndOfCyclePrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This cycle has ended with \(prompt.openCount) open task\(prompt.openCount == 1 ? "" : "s").")
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)

            if let nextID = prompt.nextCycleID, let nextName = prompt.nextCycleName {
                NexusButton(
                    variant: .primary, size: .sm,
                    action: { moveOpenTasksAndComplete(to: nextID) },
                    label: {
                        Text("Move \(prompt.openCount) open to \(nextName) & complete cycle")
                    })
            } else {
                Text("No next cycle yet — create one to roll open tasks forward, or complete this cycle from the sidebar.")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func listSection(
        _ title: String,
        tasks: [TaskItem],
        emptyText: String,
        actionTitle: String,
        action: @escaping (TaskItem) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            if tasks.isEmpty {
                Text(emptyText)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .frame(height: 28)
            } else {
                ForEach(tasks, id: \.id) { task in
                    taskRow(task, actionTitle: actionTitle) { action(task) }
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NexusColor.Text.tertiary)

            Text(task.title)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let dueAt = task.dueAt {
                Text(dueAt.formatted(date: .abbreviated, time: .omitted))
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            NexusButton(
                variant: .ghost, size: .sm, action: action,
                label: { Text(actionTitle) }
            )
            .accessibilityLabel("\(actionTitle) \(task.title)")
        }
        .frame(height: 32)
    }

    // MARK: - Data

    @MainActor
    private func reload() {
        do {
            let cycleRepository = CycleRepository(context: modelContext)
            tasksInCycle = try cycleRepository.tasks(in: cycle.id)
            nextCycle = try cycleRepository.next(now: now)
            backlog = try Self.backlogTasks(modelContext: modelContext)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Open, unassigned, non-template root tasks — the planner's candidate
    /// pool. Newest first (capture order). The store-side predicate carries the
    /// selective axes; the root/template clauses post-filter in memory because
    /// a five-clause `#Predicate` blows the type-checker budget here.
    @MainActor
    static func backlogTasks(modelContext: ModelContext) throws -> [TaskItem] {
        let openRaw = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.cycleID == nil && task.statusRaw == openRaw
        }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\TaskItem.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .filter { $0.parentTaskID == nil && !$0.isTemplate }
            .dedupedByID()
    }

    @MainActor
    private func assign(_ task: TaskItem, to cycleID: UUID?) {
        guard let repository else {
            error = "Task repository is unavailable."
            return
        }
        do {
            try repository.assignCycle(task, to: cycleID)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// The ONE sanctioned rollover path (I-C1): user-invoked, explicit, no
    /// background variant exists. Moves every open task to the next cycle,
    /// then completes this one.
    @MainActor
    private func moveOpenTasksAndComplete(to nextCycleID: UUID) {
        guard let repository else {
            error = "Task repository is unavailable."
            return
        }
        do {
            for task in openInCycle {
                try repository.assignCycle(task, to: nextCycleID)
            }
            try CycleRepository(context: modelContext).setStatus(.completed, on: cycle)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }
}
