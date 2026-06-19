import Foundation
import NexusCore
import NexusUI
import SwiftUI
import UniformTypeIdentifiers

/// Week-grid geometry per `docs/06_MODULE_CALENDAR.md` §Dimensions.
enum WeekGridMetrics {
    /// "time gutter: 56 pt".
    static let gutterWidth: CGFloat = 56
    /// "day column min width: 92 pt".
    static let dayColumnMinWidth: CGFloat = 92
    /// "hour row height: 58–64 pt".
    static let hourHeight: CGFloat = 60
    /// "all-day row height: 34 pt".
    static let allDayRowHeight: CGFloat = 34
    /// Brief: event blocks min height 42 pt.
    static let minBlockHeight: CGFloat = 42
    /// "8 AM–7 PM visible" — the default scroll position; the full day stays
    /// scrollable.
    static let firstVisibleHour = 8
    /// Full-day axis: 24 h are rendered, the spec window is just the default
    /// scroll offset.
    static let totalHours = 24
    /// "Drag to resize changes duration with snap 15 min" — the same snap is
    /// used for drop targeting.
    static let snapMinutes = 15
    /// Default scheduled-block length (1 h) when the scheduled task carries no
    /// duration estimate — the drop highlight previews a slot of this length.
    static let defaultBlockDuration: TimeInterval = 3600

    static var gridHeight: CGFloat { CGFloat(totalHours) * hourHeight }
}

/// Pure y↔time math for the week grid (unit-tested; no UI, no ambient clock).
enum WeekGridMath {
    /// Minutes from midnight for a vertical offset, snapped to the 15-minute
    /// grid and clamped inside the day.
    static func snappedMinutes(forY y: CGFloat, hourHeight: CGFloat = WeekGridMetrics.hourHeight) -> Int {
        let rawMinutes = Double(y) / Double(hourHeight) * 60
        let snap = Double(WeekGridMetrics.snapMinutes)
        let snapped = (rawMinutes / snap).rounded() * snap
        let upperBound = WeekGridMetrics.totalHours * 60 - WeekGridMetrics.snapMinutes
        return min(max(0, Int(snapped)), upperBound)
    }

    /// Concrete date for a drop at `y` inside `day`'s column.
    static func snappedDate(
        forY y: CGFloat,
        day: Date,
        calendar: Calendar,
        hourHeight: CGFloat = WeekGridMetrics.hourHeight
    ) -> Date {
        let minutes = snappedMinutes(forY: y, hourHeight: hourHeight)
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: dayStart) ?? dayStart
    }

    /// Vertical offset for a minutes-from-midnight value.
    static func yOffset(forMinutes minutes: Int, hourHeight: CGFloat = WeekGridMetrics.hourHeight) -> CGFloat {
        CGFloat(minutes) / 60 * hourHeight
    }
}

/// The drop slot a dragged task currently hovers over (one per grid).
struct WeekDropSlot: Equatable {
    let day: Date
    let minutes: Int
}

/// Custom 7-column week grid (`docs/06_MODULE_CALENDAR.md` §Week grid):
/// day-header row, 34 pt all-day pill row, then the scrollable hour axis —
/// 56 pt time gutter + 7 equal columns over a sunken background with hairline
/// grid lines. Events are glass blocks positioned by time (overlaps split
/// side-by-side via the existing `DayTimelineLayout` column algorithm); the
/// current-time line renders on today's column only. Dragging a task over a
/// column highlights the 15-min-snapped target slot; dropping schedules it
/// through `onDropTask`.
struct WeekGrid: View {

    let days: [Date]
    let calendar: Calendar
    let now: Date
    let itemsForDay: (Date) -> [TimelineItem]
    let onTapItem: (TimelineItem) -> Void
    /// `@MainActor` so the async `NSItemProvider` load in the drop delegate can
    /// hop back to the main actor with a `Sendable` closure (Swift 6).
    let onDropTask: @MainActor (UUID, Date) -> Void
    /// Tapping an empty slot in a day column: opens a new-event editor seeded at
    /// the snapped slot time (nil ⇒ no create affordance on the grid body).
    var onCreateAt: ((Date) -> Void)?
    /// Context menu actions on event/block cells; nil suppresses all menus.
    var onContextAction: ((TimelineItem, EventContextMenuAction) -> Void)?

    @State private var dropSlot: WeekDropSlot?

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            LiquidDividerLine()
            allDayRow
            LiquidDividerLine()
            hourAxis
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        // The grid uses the SAME light card surface as every other card
        // (`liquidLightCard`), so the week canvas reads as airy glass instead of
        // a darker slab clashing with the lightened cards around it. The subtle
        // hairline grid lines + colored event blocks still read on the lighter fill.
        .liquidLightCard(cornerRadius: DS.Radius.m)
    }

    // MARK: - Header (weekday + day number)

    /// Day-header band height (weekday eyebrow + day number) — reference
    /// proportions, no DS token at this scale.
    private static let headerRowHeight: CGFloat = 44

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Fixed-size spacer: a bare `Color.clear` is greedy vertically and
            // would absorb the grid's flexible height.
            Color.clear.frame(width: WeekGridMetrics.gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDate(day, inSameDayAs: now)
                VStack(spacing: 1) {
                    Text(Self.weekdayFormatter.string(from: day).uppercased())
                        .font(DS.FontToken.caption)
                        .foregroundStyle(isToday ? DS.ColorToken.accentPrimaryHover : DS.ColorToken.textTertiary)
                    Text(Self.dayNumberFormatter.string(from: day))
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(isToday ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: Self.headerRowHeight)
    }

    // MARK: - All-day row (dynamic height: 1–2 lanes × laneHeight, spec §Structure)

    /// Height of one all-day lane (pill + vertical padding).
    private static let allDayLaneHeight: CGFloat = 26
    /// Vertical gap between stacked lanes.
    private static let allDayLaneSpacing: CGFloat = 2
    /// Top/bottom padding inside the all-day row.
    private static let allDayRowPadding: CGFloat = 4

    /// Height of the "+N" overflow badge strip appended below the lanes when
    /// any column has hidden events. Sized to fit one caption glyph (~13 pt)
    /// with 2 pt top margin.
    private static let allDayOverflowStripHeight: CGFloat = 15

    private var allDayRow: some View {
        let allDayItems = DayTimelineLayout.allDayItems(forVisibleDays: days, itemsForDay: itemsForDay)
        let layout = AllDayLaneLayout.layout(
            items: allDayItems,
            visibleDays: days,
            calendar: calendar,
            maxLanes: 2
        )
        let usedLanes = max(1, (layout.bars.map(\.lane).max() ?? -1) + 1)
        let hasOverflow = !layout.overflowByColumn.isEmpty
        // Reserve an explicit badge strip when overflow is present so badges
        // never spill outside the all-day row frame.
        let rowHeight =
            CGFloat(usedLanes) * Self.allDayLaneHeight
            + CGFloat(max(0, usedLanes - 1)) * Self.allDayLaneSpacing
            + 2 * Self.allDayRowPadding
            + (hasOverflow ? Self.allDayOverflowStripHeight : 0)

        return HStack(spacing: 0) {
            Text("all-day")
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textMuted)
                .frame(width: WeekGridMetrics.gutterWidth)
            // One GeometryReader over the whole bar region; bars span across
            // columns via x-offset + width, so they cannot live in per-column
            // children.
            GeometryReader { geo in
                let columnWidth = geo.size.width / CGFloat(max(1, days.count))
                // y where the overflow badge strip begins — immediately after
                // the last lane row, still inside rowHeight.
                let badgeY =
                    Self.allDayRowPadding
                    + CGFloat(usedLanes) * Self.allDayLaneHeight
                    + CGFloat(max(0, usedLanes - 1)) * Self.allDayLaneSpacing
                    + 2
                ZStack(alignment: .topLeading) {
                    ForEach(layout.bars, id: \.item.id) { bar in
                        let accent =
                            LiquidCalendarTint(calendarHex: bar.item.colorHex)?.accent
                            ?? WeekEventClassifier.kind(for: bar.item).accent
                        let xOffset = columnWidth * CGFloat(bar.startColumn) + 2
                        let barWidth = columnWidth * CGFloat(bar.endColumn - bar.startColumn + 1) - 4
                        let yOffset =
                            Self.allDayRowPadding
                            + CGFloat(bar.lane) * (Self.allDayLaneHeight + Self.allDayLaneSpacing)
                        AllDayBarView(
                            title: bar.item.title,
                            color: accent,
                            clippedStart: bar.clippedStart,
                            clippedEnd: bar.clippedEnd
                        )
                        .frame(width: max(0, barWidth), height: Self.allDayLaneHeight)
                        .offset(x: xOffset, y: yOffset)
                    }
                    // "+N" overflow badges sit in the reserved strip below the
                    // lane rows, fully within rowHeight.
                    ForEach(Array(layout.overflowByColumn.keys.sorted()), id: \.self) { col in
                        if let count = layout.overflowByColumn[col] {
                            Text("+\(count)")
                                .font(DS.FontToken.caption)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                                .offset(x: columnWidth * CGFloat(col) + 4, y: badgeY)
                        }
                    }
                }
            }
        }
        .frame(height: rowHeight)
    }

    // MARK: - Hour axis

    private var hourAxis: some View {
        // Hoisted: one layout pass for all 7 columns per render, instead of
        // recomputing inside each column (the GeometryReader below only reads
        // the column width for lane sizing).
        let positionedByDay = positionedItemsByDay
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    gutterColumn
                    ForEach(days, id: \.self) { day in
                        dayColumn(day, positioned: positionedByDay[day] ?? [])
                    }
                }
                .frame(height: WeekGridMetrics.gridHeight)
                .background(alignment: .topLeading) { scrollAnchors }
            }
            .onAppear {
                // Default window per spec: 8 AM at the top, full day scrollable.
                proxy.scrollTo(WeekGridMetrics.firstVisibleHour, anchor: .top)
            }
        }
    }

    /// Positioned hour-axis items for every visible day, computed once per
    /// render at the grid level.
    private var positionedItemsByDay: [Date: [PositionedTimelineItem]] {
        let metrics = AxisMetrics(
            startHour: 0,
            endHour: WeekGridMetrics.totalHours,
            hourHeight: WeekGridMetrics.hourHeight,
            minItemHeight: WeekGridMetrics.minBlockHeight
        )
        return Dictionary(
            days.map { day in
                (day, DayTimelineLayout.layout(itemsForDay(day), forDay: day, metrics: metrics, calendar: calendar))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Invisible per-hour markers so `scrollTo(hour)` can land on 8 AM.
    private var scrollAnchors: some View {
        VStack(spacing: 0) {
            ForEach(0..<WeekGridMetrics.totalHours, id: \.self) { hour in
                Color.clear
                    .frame(height: WeekGridMetrics.hourHeight)
                    .id(hour)
            }
        }
    }

    private var gutterColumn: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(1..<WeekGridMetrics.totalHours, id: \.self) { hour in
                Text(Self.hourLabel(hour))
                    .font(DS.FontToken.caption.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .padding(.trailing, DS.Space.s)
                    // Center the label on its hour line (cap height ≈ 12 pt).
                    .offset(y: CGFloat(hour) * WeekGridMetrics.hourHeight - 6)
            }
        }
        .frame(width: WeekGridMetrics.gutterWidth, height: WeekGridMetrics.gridHeight)
        .accessibilityHidden(true)
    }

    private func dayColumn(_ day: Date, positioned: [PositionedTimelineItem]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                gridLines
                    // Empty-slot tap = new event at the snapped time. Sits
                    // BELOW the event blocks, so taps on a block hit the block's
                    // own button instead (only bare grid creates).
                    .modifier(EmptySlotTapModifier(day: day, calendar: calendar, onCreateAt: onCreateAt))
                eventBlocks(positioned, columnWidth: proxy.size.width)
                if let slot = dropSlot, calendar.isDate(slot.day, inSameDayAs: day) {
                    dropHighlight(slot)
                }
                if calendar.isDate(day, inSameDayAs: now) {
                    // Re-render once a minute so the line/pill keeps moving
                    // while the grid stays open (the `now` property is only a
                    // per-mount snapshot).
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        currentTimeLine(at: context.date)
                    }
                }
            }
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: WeekColumnDropDelegate(
                    day: day,
                    calendar: calendar,
                    slot: $dropSlot,
                    onDrop: onDropTask
                )
            )
        }
        // 06_MODULE_CALENDAR.md §Dimensions: "day column min width: 92 pt" —
        // columns never compress below spec at narrow windows.
        .frame(minWidth: WeekGridMetrics.dayColumnMinWidth, maxWidth: .infinity)
        .frame(height: WeekGridMetrics.gridHeight)
    }

    /// "Very subtle grid lines" (spec §Visual fidelity): hairline horizontals
    /// per hour + a hairline leading column separator.
    private var gridLines: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(width: 1, height: WeekGridMetrics.gridHeight)
            ForEach(1..<WeekGridMetrics.totalHours, id: \.self) { hour in
                Rectangle()
                    .fill(DS.ColorToken.strokeHairline)
                    .frame(height: 1)
                    .offset(y: CGFloat(hour) * WeekGridMetrics.hourHeight)
            }
        }
        .accessibilityHidden(true)
    }

    private func eventBlocks(_ positioned: [PositionedTimelineItem], columnWidth: CGFloat) -> some View {
        // 2 pt inset on each side keeps blocks off the hairline separators.
        let usableWidth = max(0, columnWidth - 4)
        return ForEach(positioned) { entry in
            let laneWidth = usableWidth / CGFloat(entry.columnCount)
            WeekEventBlock(
                item: entry.item,
                height: entry.height,
                onTap: { onTapItem(entry.item) },
                onContextAction: onContextAction.map { handler in { action in handler(entry.item, action) } }
            )
            .frame(width: max(0, laneWidth - 2), height: entry.height)
            .offset(x: 2 + CGFloat(entry.columnIndex) * laneWidth, y: entry.yOffset)
        }
    }

    /// 15-min-snapped target slot while a task drag hovers the column. The
    /// highlight previews the default 1 h block (the scheduled duration uses
    /// the task's own estimate on drop).
    private func dropHighlight(_ slot: WeekDropSlot) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
            // Drop-target fill per 03_COMPONENTS.md §Empty / Drop Zone:
            // "fill primary 8%".
            .fill(DS.ColorToken.accentPrimary.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(DS.ColorToken.accentPrimary, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .frame(height: WeekGridMetrics.hourHeight)
            .padding(.horizontal, 2)
            .offset(y: WeekGridMath.yOffset(forMinutes: slot.minutes))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Spec §Current time indicator: 1 px accent line + 20 pt pill label with
    /// 10 pt semibold text, on today's column only. `instant` comes from the
    /// enclosing minute-periodic `TimelineView`.
    private func currentTimeLine(at instant: Date) -> some View {
        let minutes = calendar.dateComponents([.hour, .minute], from: instant)
        let totalMinutes = (minutes.hour ?? 0) * 60 + (minutes.minute ?? 0)
        return HStack(spacing: DS.Space.xxs) {
            Text(WeekEventBlock.timeFormatter.string(from: instant))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(DS.ColorToken.textPrimary)
                // Never let the HStack's greedy line squeeze the label.
                .fixedSize()
                .padding(.horizontal, DS.Space.xs)
                .frame(height: 20)
                .background { Capsule(style: .continuous).fill(DS.ColorToken.accentPrimary) }
            Rectangle()
                .fill(DS.ColorToken.accentPrimary)
                .frame(height: 1)
        }
        .offset(y: WeekGridMath.yOffset(forMinutes: totalMinutes) - 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Formatters

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d"
        return formatter
    }()

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12 AM"
        case 1..<12: return "\(hour) AM"
        case 12: return "12 PM"
        default: return "\(hour - 12) PM"
        }
    }
}

/// Tracks the hovered 15-min slot while a task drag moves over a day column
/// and performs the drop: the payload is the task UUID string registered by
/// the strip's `.onDrag` source.
private struct WeekColumnDropDelegate: DropDelegate {
    let day: Date
    let calendar: Calendar
    @Binding var slot: WeekDropSlot?
    let onDrop: @MainActor (UUID, Date) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        updateSlot(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateSlot(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        slot = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let start = WeekGridMath.snappedDate(forY: info.location.y, day: day, calendar: calendar)
        slot = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let taskID = UUID(uuidString: string) else { return }
            _Concurrency.Task { @MainActor in
                onDrop(taskID, start)
            }
        }
        return true
    }

    private func updateSlot(_ info: DropInfo) {
        slot = WeekDropSlot(day: day, minutes: WeekGridMath.snappedMinutes(forY: info.location.y))
    }
}

/// A single spanning all-day bar, styled to match `LiquidPill` but rendered on
/// an `UnevenRoundedRectangle` so clipped edges (event continues beyond the
/// visible week) can be squared while outer corners remain rounded.
///
/// `clippedStart` → left edge is square; `clippedEnd` → right edge is square.
private struct AllDayBarView: View {
    let title: String
    let color: Color
    let clippedStart: Bool
    let clippedEnd: Bool

    private static let radius: CGFloat = DS.Radius.s
    private static let titleFont: Font = DS.FontToken.caption

    var body: some View {
        let r = Self.radius
        let leadingRadius: CGFloat = clippedStart ? 0 : r
        let trailingRadius: CGFloat = clippedEnd ? 0 : r
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: leadingRadius,
            bottomLeadingRadius: leadingRadius,
            bottomTrailingRadius: trailingRadius,
            topTrailingRadius: trailingRadius,
            style: .continuous
        )
        Text(title)
            .font(Self.titleFont)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(color.opacity(0.16))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(shape)
                    }
            }
            .overlay { shape.stroke(color.opacity(0.24), lineWidth: 1) }
            .shadow(color: color.opacity(0.08), radius: 4, x: 0, y: 0)
    }
}

/// Turns a tap inside a day column's grid background into a "create at this
/// slot" call, mapping the local y to a 15-min-snapped date via `WeekGridMath`.
/// Applied to the grid-lines layer (below the event blocks) so only taps on
/// bare grid create — block taps still hit the block's own button. Inert when
/// `onCreateAt` is nil (e.g. the reference snapshot).
private struct EmptySlotTapModifier: ViewModifier {
    let day: Date
    let calendar: Calendar
    let onCreateAt: ((Date) -> Void)?

    func body(content: Content) -> some View {
        if let onCreateAt {
            content
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .local)
                        .onEnded { value in
                            let start = WeekGridMath.snappedDate(
                                forY: value.location.y,
                                day: day,
                                calendar: calendar
                            )
                            onCreateAt(start)
                        }
                )
        } else {
            content
        }
    }
}
