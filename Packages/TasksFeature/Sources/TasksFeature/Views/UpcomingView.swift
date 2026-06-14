import Combine
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Dashboard-style view for open tasks due after today.
public struct UpcomingView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    public let now: Date
    public let days: Int
    public let onSelect: ((TaskItem) -> Void)?

    @State private var tasks: [TaskItem] = []
    @State private var cascadePrompt: CascadeCompletionPrompt?
    @State private var error: String?

    public init(
        now: Date = .now,
        days: Int = 7,
        onSelect: ((TaskItem) -> Void)? = nil
    ) {
        self.now = now
        self.days = days
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                heroSection

                if let error {
                    errorCard(error)
                } else if buckets.isEmpty {
                    emptyCard
                } else {
                    statsRow
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        UpcomingDayCard(
                            number: index + 1,
                            bucket: bucket,
                            now: now,
                            onSelect: onSelect,
                            onToggleDone: toggleDone
                        )
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, 42)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task(id: days) { reload() }
        .onChange(of: now) { _, _ in reload() }
        .reloadOnStoreChange { reload() }
        .cascadeCompletionConfirmation($cascadePrompt) { prompt in
            confirmCascade(prompt)
        }
    }

    private var buckets: [UpcomingDayBucket] {
        UpcomingDayBucket.make(from: tasks, now: now, calendar: .current)
    }

    @ViewBuilder
    private var heroSection: some View {
        NexusCard(.elev2, padding: 28) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("UPCOMING / NEXT \(days) DAYS")
                        .nexusType(.eyebrow)
                        // MP-2 burned: emphasis eyebrow → primary ink
                        .foregroundStyle(NexusColor.Text.primary)
                    Text("Shape the week before it starts")
                        .nexusType(.h2)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(heroSubtitle)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                UpcomingDatePocket(now: now, days: days)
                    .layoutPriority(1)
            }
        }
        .nexusHoverLift()
        .nexusSpecularHighlight()
    }

    private var heroSubtitle: String {
        if tasks.isEmpty {
            return "No open tasks are scheduled after today."
        }
        let taskWord = tasks.count == 1 ? "task" : "tasks"
        let dayWord = buckets.count == 1 ? "day" : "days"
        return "\(tasks.count) \(taskWord) across \(buckets.count) \(dayWord), grouped by due date."
    }

    private var statsRow: some View {
        LazyVGrid(columns: statColumns, alignment: .leading, spacing: 14) {
            UpcomingStatCard(label: "Scheduled", value: "\(tasks.count)", detail: "open tasks")
            UpcomingStatCard(label: "Days", value: "\(buckets.count)", detail: "active dates")
            UpcomingStatCard(label: "Priority", value: "\(highPriorityCount)", detail: "P1 tasks")
            UpcomingStatCard(label: "Repeats", value: "\(recurringCount)", detail: "recurring")
        }
    }

    private var statColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)]
    }

    private var emptyCard: some View {
        NexusCard(padding: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text("CLEAR RANGE")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                Text("Nothing is scheduled after today")
                    .nexusType(.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                Text("Capture a task with a future date and it will land here in a day-by-day plan.")
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                NexusBadge("Capture", systemImage: "plus", tone: .muted)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 220, alignment: .topLeading)
        .nexusHoverLift()
    }

    private func errorCard(_ message: String) -> some View {
        NexusCard(padding: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("UPCOMING ERROR")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                Text(message)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(4)
            }
        }
    }

    private var highPriorityCount: Int {
        tasks.filter { $0.priority == .high }.count
    }

    private var recurringCount: Int {
        tasks.filter { $0.recurrenceRule != nil }.count
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        24
        #else
        16
        #endif
    }

    private var topPadding: CGFloat {
        #if os(macOS)
        4
        #else
        16
        #endif
    }

    @MainActor
    private func reload() {
        do {
            let archivedProjectIDs =
                (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
            tasks = try UpcomingQuery()
                .next(days: days, from: now, excludingProjectIDs: archivedProjectIDs)
                .apply(in: modelContext)
            error = nil
        } catch {
            tasks = []
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func toggleDone(_ item: TaskItem) {
        guard let repository else { return }
        do {
            if item.status == .done {
                try repository.reopen(item)
            } else {
                try TaskCompletionAction.complete(item, repository: repository)
            }
            // Animate the row leaving the list on completion (see TaskListView).
            withAnimation(NexusMotion.standard) { reload() }
        } catch let error as TaskItemRepositoryError {
            if case .parentHasOpenSubtasks(let parentID, let openCount) = error, parentID == item.id {
                cascadePrompt = CascadeCompletionPrompt(task: item, openCount: openCount)
            } else {
                self.error = String(describing: error)
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func confirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let repository else { return }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: repository)
            withAnimation(NexusMotion.standard) { reload() }
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct UpcomingDayBucket: Identifiable {
    let id: Date
    let title: String
    let subtitle: String
    let tasks: [TaskItem]

    static func make(
        from tasks: [TaskItem],
        now: Date,
        calendar: Calendar
    ) -> [UpcomingDayBucket] {
        let datedTasks = tasks.compactMap { task -> (Date, TaskItem)? in
            guard let dueAt = task.dueAt else { return nil }
            return (calendar.startOfDay(for: dueAt), task)
        }

        let grouped = Dictionary(grouping: datedTasks, by: \.0)
        return grouped.keys.sorted().map { dayStart in
            let dayTasks = (grouped[dayStart] ?? [])
                .map(\.1)
                .sorted { lhs, rhs in
                    (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
                }
            return UpcomingDayBucket(
                id: dayStart,
                title: title(for: dayStart, now: now, calendar: calendar),
                subtitle: subtitle(for: dayStart),
                tasks: dayTasks
            )
        }
    }

    private static func title(for dayStart: Date, now: Date, calendar: Calendar) -> String {
        let tomorrowStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )
        if let tomorrowStart, calendar.isDate(dayStart, inSameDayAs: tomorrowStart) {
            return "Tomorrow"
        }
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        if currentWeek?.contains(dayStart) == true {
            return dayStart.formatted(.dateTime.weekday(.wide))
        }
        return dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private static func subtitle(for dayStart: Date) -> String {
        dayStart.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct UpcomingDayCard: View {
    let number: Int
    let bucket: UpcomingDayBucket
    let now: Date
    let onSelect: ((TaskItem) -> Void)?
    let onToggleDone: (TaskItem) -> Void

    var body: some View {
        NexusCard(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(number). \(bucket.title.uppercased())")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(bucket.subtitle)
                        .nexusType(.h3)
                        .foregroundStyle(NexusColor.Text.primary)
                    Text("\(bucket.tasks.count) \(bucket.tasks.count == 1 ? "task" : "tasks")")
                        .nexusType(.meta)
                        .foregroundStyle(NexusColor.Text.muted)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(bucket.tasks.enumerated()), id: \.element.id) { index, task in
                        if index > 0 {
                            Divider().overlay(NexusColor.Line.regular)
                        }
                        TaskRowView(task: task, now: now, showsDefaultTaskAssistMenu: false) {
                            onToggleDone(task)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect?(task) }
                        .taskAssistContextMenu(for: task) { actions in
                            Button(task.status == .done ? "Reopen" : "Mark done") {
                                onToggleDone(task)
                            }
                            TaskAssistMenuSection(actions: actions)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
                }
            }
        }
        .nexusHoverLift()
    }
}

private struct UpcomingStatCard: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        NexusCard(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                Text(value)
                    .nexusType(.h2)
                    .foregroundStyle(NexusColor.Text.primary)
                Text(detail)
                    .nexusType(.meta)
                    .foregroundStyle(NexusColor.Text.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .nexusHoverLift()
    }
}

private struct UpcomingDatePocket: View {
    let now: Date
    let days: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("RANGE")
                .font(NexusType.mono)
                .fontWeight(.semibold)
                .foregroundStyle(NexusColor.Text.muted)
            Text(rangeText)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(NexusColor.Background.control)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        }
    }

    private var rangeText: String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let start =
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now
        let end = calendar.date(byAdding: .day, value: max(days - 1, 0), to: start) ?? start
        let startLabel = start.formatted(.dateTime.month(.abbreviated).day())
        let endLabel = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startLabel) - \(endLabel)"
    }
}
