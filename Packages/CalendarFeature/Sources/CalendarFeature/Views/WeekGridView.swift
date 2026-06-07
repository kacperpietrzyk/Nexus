import NexusCore
import NexusUI
import SwiftUI

/// Seven-day column grid (spec §9). Each column is a compact day agenda; tapping a
/// day header drills into the Day scope (handled by the parent).
struct WeekGridView: View {
    let days: [Date]
    let calendar: Calendar
    let now: Date
    let itemsForDay: (Date) -> [TimelineItem]
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    let onTapItem: (TimelineItem) -> Void
    let onSelectDay: (Date) -> Void

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    dayColumn(day)
                }
            }
            .padding(8)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let items = itemsForDay(day).sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                onSelectDay(day)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.weekdayFormatter.string(from: day).uppercased())
                        .font(NexusType.eyebrow)
                        .foregroundStyle(NexusColor.Text.muted)
                    Text(Self.dayNumberFormatter.string(from: day))
                        .font(NexusType.h3)
                        .foregroundStyle(
                            calendar.isDate(day, inSameDayAs: now)
                                ? NexusColor.Accent.lime : NexusColor.Text.primary
                        )
                }
            }
            .buttonStyle(.plain)

            Rectangle().fill(NexusColor.Line.hairline).frame(height: 1)

            if items.isEmpty {
                Text("—")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            } else {
                ForEach(items) { item in
                    compactChip(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minWidth: 96)
    }

    private func compactChip(_ item: TimelineItem) -> some View {
        Button {
            onTapItem(item)
        } label: {
            HStack(spacing: 4) {
                Circle().fill(chipColor(item)).frame(width: 5, height: 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(TimelineItemView.timeFormatter.string(from: item.start))
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                    Text(item.title)
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous))
            .overlay(chipBorder(item))
        }
        .buttonStyle(.plain)
    }

    private func chipColor(_ item: TimelineItem) -> Color {
        switch item.kind {
        case .event: return item.colorHex.flatMap { Color(calendarHex: $0) } ?? NexusColor.Text.tertiary
        case .proposedBlock: return NexusColor.Text.muted
        case .acceptedBlock: return NexusColor.Accent.lime
        }
    }

    @ViewBuilder
    private func chipBorder(_ item: TimelineItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
        if item.kind == .proposedBlock {
            shape.strokeBorder(NexusColor.Line.strong, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        } else {
            shape.strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        }
    }

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}
