import NexusCore
import NexusUI
import SwiftUI

extension TodayDashboard {
    @ViewBuilder
    func scheduleTimeline(
        slots: [(Date, [ScheduleItem])],
        unscheduled: [TaskItem],
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            scheduleHeader

            if slots.isEmpty, unscheduled.isEmpty {
                emptyScheduleCard
            } else {
                scheduleSlotList(slots: slots, now: now)
                unscheduledSection(unscheduled, now: now)
            }
        }
    }

    private var scheduleHeader: some View {
        HStack(spacing: 8) {
            Text("Schedule")
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.primary)

            NexusBadge("Today", tone: .muted)

            Spacer()

            Text("Auto-merged from Calendar + Tasks")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
        }
        .padding(.bottom, 10)
    }

    private var emptyScheduleCard: some View {
        NexusCard(.elev1, padding: 14) {
            Text("No scheduled blocks yet")
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scheduleSlotList(slots: [(Date, [ScheduleItem])], now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(width: 1)
                .padding(.leading, 53)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(slots, id: \.0) { slot, items in
                    let isCurrent = items.contains { ScheduleGrouping.isCurrent(item: $0, now: now) }

                    NexusTimeRow(Self.scheduleTimeFormatter.string(from: slot), isCurrent: isCurrent) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items) { item in
                                scheduleCard(for: item, now: now)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unscheduledSection(_ tasks: [TaskItem], now: Date) -> some View {
        if !tasks.isEmpty {
            Divider()
                .padding(.vertical, 12)

            Text("Unscheduled")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tasks, id: \.id) { task in
                    compactTaskCard(task: task, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleCard(for item: ScheduleItem, now: Date) -> some View {
        switch item {
        case .task(let task):
            compactTaskCard(task: task, now: now)
        case .meeting(let event):
            MeetingCard(event: event, isCurrent: ScheduleGrouping.isCurrent(item: item, now: now))
        }
    }

    private func compactTaskCard(task: TaskItem, now: Date) -> some View {
        Button {
            onOpenTask?(task)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                NexusStatusGlyph(taskNexusStatus(for: task.status))
                    .padding(.top, 3)  // .top-aligned HStack: nudge 12pt glyph to bodySmall cap-height

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let startAt = task.startAt {
                            NexusBadge(Self.scheduleTimeFormatter.string(from: startAt), tone: .muted)
                        }

                        if task.priority != .none {
                            NexusBadge("P\(task.priority.rawValue)", tone: .acc)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open task \(task.title)")
    }

    private static let scheduleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
