import NexusCore
import NexusUI
import SwiftUI

/// Liquid-native month density grid (spec §Calendar — Month scope): a 6×7 cell
/// grid with Apple-style event chips and multi-day spanning bars inside one glass
/// card, matching the Week grid's look. Tapping a day drills into the Day scope.
///
/// Design (top-to-bottom inside each week row):
/// 1. Multi-day / all-day **spanning bars** — one continuous bar per event across
///    its covered columns, using `AllDayLaneLayout` (max 2 lanes). Events that
///    cross a week boundary are squared on the clipped edge, matching Apple Calendar.
/// 2. **Chips** — a compact leading color dot + truncated title for timed single-day
///    events, rendered below the bar region. Capacity is derived from the actual
///    row height via `MonthGridHelpers.chipCapacity`.
/// 3. **"+N more"** — one badge per cell summing both chip overflow and any spanning
///    bars that were pushed out of the lane cap.
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

    // MARK: - Row metrics

    /// Height of one spanning-bar lane (bar + vertical padding).
    private static let barLaneHeight: CGFloat = 18
    /// Vertical gap between stacked bar lanes.
    private static let barLaneSpacing: CGFloat = 2
    /// Vertical padding above the first bar lane inside the bar region.
    private static let barRegionTopPadding: CGFloat = 2
    /// Maximum spanning-bar lanes shown per row (overflow folded into "+N more").
    private static let maxBarLanes = 2

    /// Upper clamp on chips shown per cell (overridden downward by available height).
    static let maxChipsVisible = 3

    // MARK: - Day-number height measurement
    //
    // All cells in all rows share the same day-number font (`DS.FontToken.caption`),
    // so we measure it once at the grid level via a hidden `Text("0")` with the same
    // font and bottom padding. The measured height drives the bar y-offset for every
    // row, keeping bars registered exactly below the day number.
    @State private var dayNumberHeight: CGFloat = 0

    // MARK: - Layout helpers

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
                    weekRow(week)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        // Hidden day-number measurer: same font + bottom padding as in `cell(_:)`.
        // Positioned off-screen so it never paints; its GeometryReader background
        // fires once the font is resolved and writes to `dayNumberHeight`.
        .background(alignment: .topLeading) {
            Text("0")
                .font(DS.FontToken.caption)
                .padding(.bottom, DS.Space.xxs)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DayNumberHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
                .hidden()
        }
        .onPreferenceChange(DayNumberHeightKey.self) { height in
            dayNumberHeight = height
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidLightCard(cornerRadius: DS.Radius.m)
    }

    // MARK: - Week-day header

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

    // MARK: - Week row

    /// One horizontal row of 7 day cells, with the spanning-bar overlay on top.
    ///
    /// Layout layers (bottom to top):
    /// - `HStack` of 7 `cell(...)` views
    /// - Spanning bar overlay (absolute-positioned via `GeometryReader`)
    ///
    /// **Geometry contract:**
    /// - `cellWidth = (rowWidth - (n-1)*spacing) / n` — accounts for `HStack` gaps
    ///   so columns in the overlay register with the cell left edges exactly.
    /// - Bar y-base = `cellPad + dayNumberHeight + DS.Space.xxs + barRegionTopPadding`
    ///   — identical to the top of the `Color.clear` reservation inside each cell,
    ///   so the overlay and the in-cell content stay vertically aligned.
    private func weekRow(_ week: [Date]) -> some View {
        // Compute the bar layout once for the full row so cells can reserve the
        // same vertical space for the bar region and the overlay can position bars.
        let allDayItems = DayTimelineLayout.allDayItems(forVisibleDays: week, itemsForDay: itemsForDay)
        let barLayout = AllDayLaneLayout.layout(
            items: allDayItems,
            visibleDays: week.map { calendar.startOfDay(for: $0) },
            calendar: calendar,
            maxLanes: Self.maxBarLanes
        )
        let usedLanes = (barLayout.bars.map(\.lane).max() ?? -1) + 1
        let barRegionHeight: CGFloat =
            usedLanes > 0
            ? Self.barRegionTopPadding
                + CGFloat(usedLanes) * Self.barLaneHeight
                + CGFloat(max(0, usedLanes - 1)) * Self.barLaneSpacing
            : 0

        return GeometryReader { geo in
            let n = week.count
            let spacing = DS.Space.xs
            // Correct column width accounting for (n-1) spacing gaps.
            let cellWidth =
                n > 1
                ? (geo.size.width - CGFloat(n - 1) * spacing) / CGFloat(n)
                : geo.size.width
            // Adaptive chip capacity: derive available height inside the cell.
            // Subtracts: cell top pad + day-number row + bar region + chip-gap + cell bottom pad.
            let chipSlotHeight =
                geo.size.height
                - DS.Space.xs  // cell top padding
                - dayNumberHeight  // day number + bottom pad
                - barRegionHeight  // bar lanes reservation
                - (barRegionHeight > 0 ? DS.Space.xxs : 0)  // gap above chips
                - DS.Space.xs  // cell bottom padding
            let adaptiveCap = min(
                Self.maxChipsVisible,
                MonthGridHelpers.chipCapacity(availableHeight: chipSlotHeight)
            )

            ZStack(alignment: .topLeading) {
                // Bottom layer: cell backgrounds + day numbers + chips + "+N more".
                HStack(spacing: spacing) {
                    ForEach(week, id: \.self) { day in
                        let col = week.firstIndex(of: day) ?? 0
                        let barOverflow = barLayout.overflowByColumn[col] ?? 0
                        cell(day, barRegionHeight: barRegionHeight, barOverflow: barOverflow, chipCap: adaptiveCap)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Top layer: spanning bars, hit-testing disabled so cell buttons
                // still receive taps underneath.
                barsOverlay(
                    bars: barLayout.bars,
                    cellWidth: cellWidth,
                    spacing: spacing,
                    barYBase: DS.Space.xs + dayNumberHeight + Self.barRegionTopPadding
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Bars overlay

    /// Absolute-positioned spanning-bar tiles for one week row.
    ///
    /// Geometry (each bar):
    /// - `x = col*(cellWidth+spacing) + 2` — 2 pt inset from column left edge
    /// - `w = span*(cellWidth+spacing) − spacing − 4` — 2 pt inset each side
    /// - `y = barYBase + lane*(barLaneHeight+barLaneSpacing)` — stacked below day number
    @ViewBuilder
    private func barsOverlay(
        bars: [AllDayBar],
        cellWidth: CGFloat,
        spacing: CGFloat,
        barYBase: CGFloat
    ) -> some View {
        ForEach(bars, id: \.item.id) { bar in
            let accent =
                LiquidCalendarTint(calendarHex: bar.item.colorHex)?.accent
                ?? WeekEventClassifier.kind(for: bar.item).accent
            let xOffset = CGFloat(bar.startColumn) * (cellWidth + spacing) + 2
            let barWidth =
                CGFloat(bar.endColumn - bar.startColumn + 1) * (cellWidth + spacing)
                - spacing - 4
            let yOffset =
                barYBase
                + CGFloat(bar.lane) * (Self.barLaneHeight + Self.barLaneSpacing)
            AllDayBarView(
                title: bar.item.title,
                color: accent,
                clippedStart: bar.clippedStart,
                clippedEnd: bar.clippedEnd
            )
            .frame(width: max(0, barWidth), height: Self.barLaneHeight)
            .offset(x: xOffset, y: yOffset)
        }
    }

    // MARK: - Day cell

    private func cell(
        _ day: Date,
        barRegionHeight: CGFloat,
        barOverflow: Int,
        chipCap: Int
    ) -> some View {
        let allItems = itemsForDay(day)
        let timedItems = MonthGridHelpers.timedItems(from: allItems)
        // If everything fits, show all chips with no badge. If there is overflow,
        // reserve one chip slot for the badge (worst-case one chip shown with "+N").
        let shownChips: Int
        let chipOverflow: Int
        if timedItems.count <= chipCap {
            shownChips = timedItems.count
            chipOverflow = 0
        } else {
            shownChips = max(0, chipCap - 1)
            chipOverflow = timedItems.count - shownChips
        }
        let totalOverflow = chipOverflow + barOverflow
        let inMonth = calendar.isDate(day, equalTo: anchor, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: now)

        let state = CellState(
            timedItems: timedItems,
            shownChips: shownChips,
            totalOverflow: totalOverflow
        )
        return Button {
            onSelectDay(day)
        } label: {
            cellContent(
                day: day,
                state: state,
                barRegionHeight: barRegionHeight,
                inMonth: inMonth,
                isToday: isToday
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(Self.accessibilityFormatter.string(from: day)), \(allItems.count) items"
        )
    }

    /// Pre-computed display state for one day cell (grouped to keep `cellContent`
    /// within the SwiftLint parameter-count limit of 5).
    private struct CellState {
        let timedItems: [TimelineItem]
        let shownChips: Int
        let totalOverflow: Int
    }

    @ViewBuilder
    private func cellContent(
        day: Date,
        state: CellState,
        barRegionHeight: CGFloat,
        inMonth: Bool,
        isToday: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day number always at the top; `.padding(.bottom)` must match
            // the hidden measurer in `body` so bar y-offsets stay correct.
            Text(Self.dayNumberFormatter.string(from: day))
                .font(DS.FontToken.caption)
                .foregroundStyle(dayNumberColor(inMonth: inMonth, isToday: isToday))
                .padding(.bottom, DS.Space.xxs)

            // Reserve space for spanning bars so all cells in the row stay
            // vertically aligned (the bars themselves are in the overlay).
            if barRegionHeight > 0 {
                Color.clear.frame(height: barRegionHeight)
            }

            // Chips for timed single-day events.
            if state.shownChips > 0 {
                VStack(alignment: .leading, spacing: MonthGridHelpers.chipSpacing) {
                    ForEach(
                        Array(state.timedItems.prefix(state.shownChips).enumerated()),
                        id: \.offset
                    ) { _, item in
                        chip(item)
                    }
                }
                .padding(.top, barRegionHeight > 0 ? DS.Space.xxs : 0)
            }

            // "+N more" badge when chips or bars overflow.
            if state.totalOverflow > 0 {
                Text("+\(state.totalOverflow) more")
                    .font(DS.FontToken.caption.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .padding(.top, DS.Space.xxs)
            }

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

    // MARK: - Chip

    /// A compact event chip: a 4 pt leading color marker + truncated title.
    /// Mirrors the dot-color logic from the old `dots(for:)` but inline since
    /// chips are a structurally different view.
    private func chip(_ item: TimelineItem) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(chipColor(item))
                .frame(width: 4, height: 4)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: MonthGridHelpers.chipHeight, alignment: .leading)
    }

    private func chipColor(_ item: TimelineItem) -> Color {
        switch item.kind {
        case .event:
            return item.colorHex.flatMap { Color(calendarHexDesaturated: $0) }
                ?? DS.ColorToken.textTertiary
        case .proposedBlock: return DS.ColorToken.textMuted
        case .acceptedBlock: return DS.ColorToken.accentPrimary
        case .seriesPreview: return DS.ColorToken.textMuted
        }
    }

    private func dayNumberColor(inMonth: Bool, isToday: Bool) -> Color {
        if isToday { return DS.ColorToken.accentPrimaryHover }
        return inMonth ? DS.ColorToken.textSecondary : DS.ColorToken.textMuted
    }

    // MARK: - Static resources

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

// MARK: - PreferenceKey for day-number height measurement

/// Propagates the measured height of the day-number Text upward so the bar
/// overlay y-offset can be aligned below it without hardcoding font metrics.
private struct DayNumberHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Pure helpers (testable without SwiftUI)

/// Pure partitioning logic extracted so unit tests can exercise it without a
/// SwiftUI host. No UI, no ambient clock.
enum MonthGridHelpers {
    /// Height of one event chip row — kept here (nonisolated) so `chipCapacity`
    /// can use it as a default without referencing the `@MainActor`-isolated
    /// `LiquidMonthGrid` static properties.
    static let chipHeight: CGFloat = 14
    /// Vertical gap between stacked chips inside a cell.
    static let chipSpacing: CGFloat = 1

    /// Timed (non-all-day) items from a day's item list.
    /// These are what render as in-cell chips; all-day items are handled by the
    /// spanning-bar layer.
    static func timedItems(from items: [TimelineItem]) -> [TimelineItem] {
        items.filter { !$0.isAllDay }
    }

    /// How many chip rows fit in `availableHeight` below the bar region, given
    /// chip height and spacing constants.
    static func chipCapacity(
        availableHeight: CGFloat,
        chipHeight: CGFloat = MonthGridHelpers.chipHeight,
        chipSpacing: CGFloat = MonthGridHelpers.chipSpacing
    ) -> Int {
        guard availableHeight >= chipHeight else { return 0 }
        // Each chip after the first costs chipHeight + chipSpacing.
        let rest = chipHeight + chipSpacing
        return 1 + max(0, Int((availableHeight - chipHeight) / rest))
    }
}
