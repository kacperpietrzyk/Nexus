import NexusCore
import NexusUI
import SwiftData
import SwiftUI

struct WatchAgendaView: View {
    @Environment(\.modelContext) private var modelContext
    let onCapture: () -> Void
    let onAskNexus: () -> Void

    @Query(
        filter: #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.dueAt != nil
        }, sort: \TaskItem.dueAt)
    private var openWithDue: [TaskItem]

    @Query(
        filter: #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.lastCompletedAt != nil
        },
        sort: \TaskItem.lastCompletedAt,
        order: .reverse
    )
    private var completed: [TaskItem]

    @State private var selected: TaskItem?
    @State private var actions: WatchTaskActions?
    @State private var pendingUndo: PendingUndo?

    init(
        onCapture: @escaping () -> Void = {},
        onAskNexus: @escaping () -> Void = {}
    ) {
        self.onCapture = onCapture
        self.onAskNexus = onAskNexus
    }

    private struct PendingUndo: Equatable {
        let taskID: UUID
        let title: String
        let expiresAt: Date
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let result = makeAgendaResult(now: now)
            let visibleOverdueCount = overdueCount(in: result.agenda, now: now)
            let visibleTodayCount = result.agenda.count - visibleOverdueCount

            ZStack(alignment: .top) {
                Group {
                    if result.agenda.isEmpty && result.recentlyDone.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(NexusColor.Text.secondary)
                            Text("No tasks")
                                .font(NexusType.h3)
                                .foregroundStyle(NexusColor.Text.primary)
                            Text("Add by dictation or ask Nexus.")
                                .font(NexusType.bodySmall)
                                .foregroundStyle(NexusColor.Text.tertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            WatchQuickActions(
                                onCapture: onCapture,
                                onAskNexus: onAskNexus
                            )
                            .padding(.top, 2)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            WatchAgendaSummary(
                                overdueCount: visibleOverdueCount,
                                todayCount: visibleTodayCount,
                                doneCount: result.recentlyDone.count,
                                onCapture: onCapture,
                                onAskNexus: onAskNexus
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 8, trailing: 6))
                            .listRowBackground(Color.clear)

                            if !result.agenda.isEmpty {
                                Section {
                                    ForEach(result.agenda, id: \.id) { task in
                                        Button {
                                            selected = task
                                        } label: {
                                            WatchAgendaRow(
                                                task: task,
                                                now: now,
                                                onMarkedDone: { handleMarkedDone($0, now: now) }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            if !result.recentlyDone.isEmpty {
                                Section("Done today") {
                                    ForEach(result.recentlyDone, id: \.id) { task in
                                        Button {
                                            selected = task
                                        } label: {
                                            WatchAgendaRow(
                                                task: task,
                                                now: now,
                                                onReopened: { _ in pendingUndo = nil }
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }

                if let undo = pendingUndo, undo.expiresAt > now {
                    Button {
                        Task {
                            if let task = task(forID: undo.taskID) {
                                try? await actions?.reopen(task)
                            }
                            withAnimation(NexusMotion.standard) {
                                pendingUndo = nil
                            }
                        }
                    } label: {
                        Text("Undo: \(undo.title)")
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            // Linear flat: Background.raised is the principled
                            // elevated surface for a floating undo banner on a
                            // near-black Watch ground. No glass alpha needed.
                            .background(
                                NexusColor.Background.raised,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(NexusMotion.standard, value: pendingUndo)
            .sheet(item: $selected) { task in
                WatchTaskDetailSheet(task: task)
                    .environment(\.watchTaskActions, actions)
            }
            .environment(\.watchTaskActions, actions)
            .onAppear {
                if actions == nil {
                    actions = WatchTaskActions(
                        context: modelContext,
                        bridge: WatchPhoneBridge.shared
                    )
                }
            }
        }
    }

    private func makeAgendaResult(now: Date) -> AgendaResult {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let openTasks = openWithDue.filter { $0.status == .open }
        let overdue = openTasks.filter { ($0.dueAt ?? .distantFuture) < startOfDay }
        let today = openTasks.filter { task in
            guard let due = task.dueAt else { return false }
            return due >= startOfDay && due < startOfTomorrow
        }
        let recentlyDone = completed.filter { task in
            guard let stamp = task.lastCompletedAt else { return false }
            return task.status == .done
                && stamp >= startOfDay
                && stamp < startOfTomorrow
        }

        return WatchAgendaSelector.pick(
            overdue: overdue,
            today: today,
            recentlyDone: recentlyDone,
            now: now
        )
    }

    private func handleMarkedDone(_ task: TaskItem, now: Date) {
        let stamp = now.addingTimeInterval(5)
        withAnimation(NexusMotion.standard) {
            pendingUndo = PendingUndo(taskID: task.id, title: task.title, expiresAt: stamp)
        }
        Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(5))
            if pendingUndo?.expiresAt == stamp {
                withAnimation(NexusMotion.standard) {
                    pendingUndo = nil
                }
            }
        }
    }

    private func task(forID id: UUID) -> TaskItem? {
        completed.first(where: { $0.id == id })
            ?? openWithDue.first(where: { $0.id == id })
    }

    private func overdueCount(in tasks: [TaskItem], now: Date) -> Int {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return tasks.filter { ($0.dueAt ?? .distantFuture) < startOfDay }.count
    }
}

private struct WatchAgendaSummary: View {
    let overdueCount: Int
    let todayCount: Int
    let doneCount: Int
    let onCapture: () -> Void
    let onAskNexus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(NexusType.h3)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(NexusType.meta)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if overdueCount > 0 {
                    Text("\(overdueCount)")
                        .font(NexusType.h2)
                        .foregroundStyle(NexusColor.Text.primary)
                        .accessibilityLabel("\(overdueCount) overdue")
                }
            }

            WatchQuickActions(
                onCapture: onCapture,
                onAskNexus: onAskNexus
            )
        }
        .padding(10)
        .background(
            NexusColor.Background.control,
            in: RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
        )
    }

    private var title: String {
        if overdueCount > 0 {
            return "\(overdueCount) overdue"
        }
        if todayCount > 0 {
            return "\(todayCount) today"
        }
        return "Agenda clear"
    }

    private var subtitle: String {
        if todayCount > 0 && doneCount > 0 {
            return "\(todayCount) open · \(doneCount) done"
        }
        if todayCount > 0 {
            return "Next tasks are ready"
        }
        if doneCount > 0 {
            return "\(doneCount) done today"
        }
        return "Capture is one tap away"
    }
}

private struct WatchQuickActions: View {
    let onCapture: () -> Void
    let onAskNexus: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Lime: single primary action on this surface (voice capture).
            // limeInk foreground for contrast on the lime fill.
            Button(action: onCapture) {
                Label("Capture", systemImage: "mic.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NexusColor.Accent.limeInk)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(NexusColor.Accent.lime)
            .accessibilityLabel("Capture task")

            Button(action: onAskNexus) {
                Label("Ask", systemImage: "sparkles")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
            .tint(NexusColor.Text.secondary)
            .accessibilityLabel("Ask Nexus")
        }
    }
}
