import NexusCore
import NexusUI
import SwiftUI

/// Liquid-native month density grid (spec §Calendar — Month scope): a 6×7 cell
/// grid of per-day event dots inside one glass card, matching the Week grid's
/// look. Tapping a day drills into the Day scope.
///
/// This is the Liquid counterpart of the legacy `MonthGridView` (which stays on
/// the old `NexusColor` tokens for the iOS `CalendarView`); the two are kept
/// separate so restyling here never leaks into that still-live surface.
///
/// Cells use a flat translucent tint rather than a per-cell glass material — 42
/// `NSVisualEffectView`s would be needlessly expensive; the surrounding card
/// provides the glass, the cells are subtle sub-divisions on top of it.
struct LiquidMonthGrid: View {
    let days: [Date]
    let anchor: Date
    let calendar: Calendar
    let now: Date
    let itemsForDay: (Date) -> [TimelineItem]
    let onSelectDay: (Date) -> Void

    /// Days chunked into week rows so each row can share the available height
    /// (a `LazyVGrid` only flexes width — rows would collapse to content).
    private var weeks: [[Date]] {
        stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
    }

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            weekdayHeader
            VStack(spacing: DS.Space.xs) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: DS.Space.xs) {
                        ForEach(week, id: \.self) { day in
                            cell(day)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidLightCard(cornerRadius: DS.Radius.m)
    }

    private var weekdayHeader: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
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
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(Self.dayNumberFormatter.string(from: day))
                    .font(DS.FontToken.caption)
                    .foregroundStyle(dayNumberColor(inMonth: inMonth, isToday: isToday))
                dots(for: items, inMonth: inMonth)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DS.Space.xs)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(isToday ? DS.ColorToken.accentPrimary.opacity(0.10) : Color.white.opacity(0.022))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .strokeBorder(
                        isToday ? DS.ColorToken.accentPrimary.opacity(0.45) : DS.ColorToken.strokeHairline,
                        lineWidth: 1
                    )
            }
            .opacity(inMonth ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.accessibilityFormatter.string(from: day)), \(items.count) items")
    }

    @ViewBuilder
    private func dots(for items: [TimelineItem], inMonth: Bool) -> some View {
        if items.isEmpty {
            if inMonth {
                Circle()
                    .fill(DS.ColorToken.textMuted.opacity(0.6))
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
                        .font(DS.FontToken.caption.monospacedDigit())
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }
        }
    }

    private func dotColor(_ item: TimelineItem) -> Color {
        switch item.kind {
        case .event: return item.colorHex.flatMap { Color(calendarHexDesaturated: $0) } ?? DS.ColorToken.textTertiary
        case .proposedBlock: return DS.ColorToken.textMuted
        case .acceptedBlock: return DS.ColorToken.accentPrimary
        case .seriesPreview: return DS.ColorToken.textMuted
        }
    }

    private func dayNumberColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return DS.ColorToken.accentPrimaryHover }
        return inMonth ? DS.ColorToken.textSecondary : DS.ColorToken.textMuted
    }

    static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d"
        return formatter
    }()

    static let accessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        return formatter
    }()
}
