import NexusCore
import NexusUI
import SwiftUI

/// Month density grid (spec §9): a 6×7 cell grid showing per-day item counts /
/// dots. Tapping a day drills into the Day scope.
struct MonthGridView: View {
    let days: [Date]
    let anchor: Date
    let calendar: Calendar
    let now: Date
    let itemsForDay: (Date) -> [TimelineItem]
    let onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    cell(day)
                }
            }
        }
        .padding(8)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(NexusType.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let items = itemsForDay(day)
        let inMonth = calendar.isDate(day, equalTo: anchor, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        return Button {
            onSelectDay(day)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dayNumberFormatter.string(from: day))
                    .font(NexusType.caption)
                    .foregroundStyle(dayNumberColor(inMonth: inMonth, isToday: isToday))
                dots(for: items, inMonth: inMonth)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .padding(6)
            .background(
                isToday ? NexusColor.Background.control : NexusColor.Background.panel,
                in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                    .strokeBorder(
                        isToday ? NexusColor.Accent.lime.opacity(0.4) : NexusColor.Line.hairline,
                        lineWidth: 1
                    )
            )
            .opacity(inMonth ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.accessibilityFormatter.string(from: day)), \(items.count) items")
    }

    @ViewBuilder
    private func dots(for items: [TimelineItem], inMonth: Bool) -> some View {
        if items.isEmpty {
            // Subtle "nothing scheduled" marker — a faint dot, not a blank gap.
            // Only within the current month, so spill days stay clean and the
            // grid doesn't read as a field of noise.
            if inMonth {
                Circle()
                    .fill(NexusColor.Text.disabled)
                    .frame(width: 3, height: 3)
                    .accessibilityHidden(true)
            }
        } else {
            HStack(spacing: 2) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                    Circle().fill(dotColor(item)).frame(width: 4, height: 4)
                }
                if items.count > 4 {
                    Text("+\(items.count - 4)")
                        .font(NexusType.metaMono)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
        }
    }

    private func dotColor(_ item: TimelineItem) -> Color {
        switch item.kind {
        case .event: return item.colorHex.flatMap { Color(calendarHexDesaturated: $0) } ?? NexusColor.Text.tertiary
        case .proposedBlock: return NexusColor.Text.muted
        case .acceptedBlock: return NexusColor.Accent.lime
        case .seriesPreview: return NexusColor.Text.muted
        }
    }

    private func dayNumberColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return NexusColor.Accent.lime }
        return inMonth ? NexusColor.Text.secondary : NexusColor.Text.muted
    }

    static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    static let accessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
