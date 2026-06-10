import NexusCore
import NexusUI
import SwiftUI

// MARK: - Embedded-Today day-timeline right rail
//
// The embedded (Nexus shell) Today RIGHT RAIL: a SCROLLABLE full-day (0–24)
// timeline — hour grid, schedule blocks, free-time labels, an all-day strip,
// and a live now-line via `TimelineView(.animation(paused: reduce))`. The
// rail auto-scrolls to the current hour on appear.
//
// HISTORY: the original surface mirrored the Lab `DayTimeline` oracle's
// fixed, non-scrolling 9:00–20:00 window, which silently DROPPED every event
// outside those hours (early-morning, evening, all-day). That window was an
// approved product change away from oracle parity — the rail now covers the
// whole day (0–24) and never drops an item. The right rail remains
// `DayTimeline`-only on the embedded path; the standalone / iOS-compact
// paths still mount the capture-pills + digest `rightRail` unchanged.
//
// UI-only: renders existing `scheduleTasks` + `todaysEvents`; no new query,
// predicate, repo, facet, or behaviour. Achromatic: every tone is a
// `NexusColor.*` token; no `Lab*` import or type.

extension TodayDashboard {

    /// The embedded (Nexus shell) Today right rail. Mounted only when
    /// `chrome == .embedded` (see `embeddedRegularBody`); the standalone /
    /// iOS-compact paths keep the capture-pills + digest `rightRail`.
    ///
    /// Mirrors the oracle's right-rail container: 18pt padding, 320pt fixed
    /// width, glass on a RoundedRect(18). The blocks/now/free-time are all
    /// derived from the dashboard's already-loaded `scheduleTasks` +
    /// `todaysEvents` — no new data source.
    var embeddedTimelineRail: some View {
        // The rail FILLS the content area's full height, which becomes the
        // scroll viewport for `EmbeddedDayTimeline`'s fixed 0–24 hour axis.
        let built = Self.embeddedTimelineBlocks(
            tasks: scheduleTasks,
            events: todaysEvents
        )
        return EmbeddedDayTimeline(
            blocks: built.blocks,
            allDay: built.allDay
        )
        .padding(18)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        // Liquid re-skin (container level): keep the Inbox reader pane's
        // right-pane idiom (r3 corner), but the liquid glass card recipe
        // replaces the opaque `Background.raised` slab + manual Line.regular
        // stroke + s1 shadow (the slab clashed inside the glass content shell).
        .liquidGlass(.card, radius: NexusRadius.r3)
    }

    /// A single timeline block in fractional-hour coordinates on the full-day
    /// (0–24) axis. Pure presentation geometry. `a`/`b` are start/end as
    /// `hour + minute/60`; `time` is the "HH:mm" start label. The `id`
    /// (`"task:<uuid>"` / `"event:<id>"`) is an origin-disambiguation key, not
    /// SwiftUI identity (the Canvas iterates with a bare `for`, no `ForEach`).
    struct EmbeddedTimelineBlock {
        let id: String
        let a: Double
        let b: Double
        let title: String
        /// "HH:mm" start label — same formatter as the Canvas start indicator.
        let time: String
        /// "HH:mm" end label — from the end `Date`.
        let endTime: String
    }

    /// An all-day event for the strip pinned above the hour axis (all-day
    /// events have no meaningful hour-grid position, so they live here rather
    /// than at 00:00). `id` mirrors the builder's `"event:<id>"` convention.
    struct EmbeddedAllDayItem {
        let id: String
        let title: String
    }

    /// Build the timed blocks + all-day items from EXISTING schedule data the
    /// dashboard already loaded — `scheduleTasks` + `todaysEvents` (set in
    /// `reloadScheduleData()`). No new query/predicate/repo.
    ///
    /// A task contributes a block only if it has a real `startAt` (the same
    /// "scheduled" rule `ScheduleGrouping` uses). Its end is
    /// `endAt ?? dueAt ?? start`. Tasks are never all-day. Timed events use
    /// their `start`/`end` directly; an event with `isAllDay == true` is
    /// routed to the all-day strip instead of being placed on the hour axis.
    ///
    /// NO WINDOW GUARD: every timed item renders at its TRUE wall-clock
    /// position on the full-day (0–24) axis — a 07:00 or 22:00 item is no
    /// longer dropped. A zero/negative-length item still gets a small
    /// synthetic span (`+0.25h`) so the rect is never degenerate or inverted.
    /// `fractionalHour` reads only wall-clock `.hour`/`.minute` (DST-correct:
    /// 14:00 is always 14:00 regardless of any UTC offset shift); a
    /// cross-midnight item collapses to a short slab at its start hour rather
    /// than wrapping past midnight.
    static func embeddedTimelineBlocks(
        tasks: [TaskItem],
        events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> (blocks: [EmbeddedTimelineBlock], allDay: [EmbeddedAllDayItem]) {
        func fractionalHour(_ date: Date) -> Double {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        }

        func makeBlock(
            id: String,
            start: Date,
            end: Date,
            title: String
        ) -> EmbeddedTimelineBlock {
            let a = fractionalHour(start)
            // A zero/negative-length item still gets a minimum visible slab
            // (the Canvas also enforces `max(20, …)` height); use a small
            // synthetic span so the rect is never degenerate or inverted.
            let b = max(fractionalHour(end), a + 0.25)
            return EmbeddedTimelineBlock(
                id: id,
                a: a,
                b: b,
                title: title,
                time: Self.embeddedTimelineTimeFormatter.string(from: start),
                endTime: Self.embeddedTimelineTimeFormatter.string(from: end)
            )
        }

        var blocks: [EmbeddedTimelineBlock] = []
        var allDay: [EmbeddedAllDayItem] = []

        for task in tasks where task.deletedAt == nil {
            guard let start = task.startAt else { continue }
            let end = task.endAt ?? task.dueAt ?? start
            blocks.append(
                makeBlock(
                    id: "task:\(task.id.uuidString)",
                    start: start,
                    end: end,
                    title: task.title
                )
            )
        }

        for event in events {
            if event.isAllDay {
                allDay.append(
                    EmbeddedAllDayItem(id: "event:\(event.id)", title: event.title)
                )
            } else {
                blocks.append(
                    makeBlock(
                        id: "event:\(event.id)",
                        start: event.start,
                        end: event.end,
                        title: event.title
                    )
                )
            }
        }

        return (blocks.sorted { $0.a < $1.a }, allDay)
    }

    static let embeddedTimelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Free-time label for the gap between `nowFrac` and the next block
    /// strictly after it, or `nil` to omit. Bounds are clamped to
    /// `[windowStart, windowEnd]`. Threshold is `>= 30` minutes: shorter gaps
    /// are suppressed; `>= 30` & `< 60` renders `"free · Nm"`, `>= 60` renders
    /// `"free · Hh Mm"`. The window defaults to the full day (`0…24`). Pure
    /// function — no view state; unit-coverable.
    static func embeddedFreeTimeLabel(
        nowFrac: Double,
        blocks: [EmbeddedTimelineBlock],
        windowStart: Double = 0.0,
        windowEnd: Double = 24.0
    ) -> (text: String, midFrac: Double)? {
        let gapStart = max(nowFrac, windowStart)
        guard gapStart < windowEnd else { return nil }
        guard
            let next =
                blocks
                .filter({ $0.a > gapStart })
                .min(by: { $0.a < $1.a })
        else { return nil }
        let gapEnd = min(next.a, windowEnd)
        let minutes = Int(((gapEnd - gapStart) * 60).rounded())
        guard minutes >= 30 else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        let text: String
        if hours > 0 {
            text = "free · \(hours)h \(mins)m"
        } else {
            text = "free · \(mins)m"
        }
        return (text, (gapStart + gapEnd) / 2)
    }

    /// Ordered VoiceOver label strings for the day-timeline Canvas — one per
    /// schedule block (`"<title>, <start>–<end>"`), plus a now-line element
    /// (`"Now, <HH:mm>"`) interleaved at its wall-clock position when `now`
    /// falls within `[windowStart, windowEnd]`. The window defaults to the
    /// full day (`0…24`), so the now element is emitted for any time. Pure +
    /// deterministic on `calendar`; called from both the view's
    /// `.accessibilityRepresentation` and the test suite (single source).
    static func embeddedTimelineAccessibilityLabels(
        blocks: [EmbeddedTimelineBlock],
        now: Date,
        windowStart: Double = 0.0,
        windowEnd: Double = 24.0,
        calendar: Calendar = .current
    ) -> [String] {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let nowHour = comps.hour ?? 0
        let nowMinute = comps.minute ?? 0
        let nowFrac = Double(nowHour) + Double(nowMinute) / 60.0
        let nowInWindow = nowFrac >= windowStart && nowFrac <= windowEnd
        // Format using the same "HH:mm" pattern as the Canvas, but against the
        // supplied `calendar`'s timezone so tests using a fixed UTC calendar are
        // deterministic (same as `embeddedTimelineBlocks` taking `calendar:`).
        let nowLabel = String(format: "%02d:%02d", nowHour, nowMinute)

        var result: [String] = []
        var nowInserted = false

        for block in blocks {
            // Insert the now-line element at its chronological position.
            if nowInWindow && !nowInserted && nowFrac <= block.a {
                result.append("Now, \(nowLabel)")
                nowInserted = true
            }
            result.append("\(block.title), \(block.time)–\(block.endTime)")
        }

        // Now is after all blocks (or there are no blocks) — append at end.
        if nowInWindow && !nowInserted {
            result.append("Now, \(nowLabel)")
        }

        return result
    }
}

// MARK: - DayTimeline Canvas (Today-specific; full-day scrollable rail)

/// The day-timeline rail: a SCROLLABLE full-day (0–24) Canvas inside a
/// `ScrollView`, with an all-day strip pinned above and a live now-line.
/// Presentation-pure — takes the pre-derived `blocks` + `allDay` lists; the
/// now-line + free-time recompute from `tl.date` inside the `TimelineView`
/// closure so they stay live without persisted state. Replaces the original
/// fixed-height 9–20 Canvas; the scroll/auto-scroll pattern mirrors
/// `CalendarFeature.DayGridView` without importing it (feature modules stay
/// independent — see `CLAUDE.md`). `private` — never API.
private struct EmbeddedDayTimeline: View {
    let blocks: [TodayDashboard.EmbeddedTimelineBlock]
    let allDay: [TodayDashboard.EmbeddedAllDayItem]

    private let startH = 0.0
    private let endH = 24.0
    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 26

    /// Total height of the 0–24 hour axis — the Canvas is laid out at exactly
    /// this height, taller than the viewport, so the day scrolls.
    private var axisHeight: CGFloat { CGFloat(endH - startH) * hourHeight }

    // Reduce-Motion gated AT SOURCE: the `paused:` argument freezes the
    // `TimelineView` schedule; `reduce` is also read in `drawNowLine` to pin
    // the pulse to its resting value (steady, non-animating now-line).
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Fractional hour `t` → absolute pixel offset on the 0–24 axis (the
    /// affine form keeps the axis bounds a single source).
    private func y(_ t: Double) -> CGFloat {
        CGFloat(t - startH) * hourHeight
    }

    /// "HH:mm" for `date` — the live current-time indicator label. Reuses
    /// the same formatter the block builder uses.
    private func nowLabel(_ date: Date) -> String {
        TodayDashboard.embeddedTimelineTimeFormatter.string(from: date)
    }

    /// `date` as fractional hours (`hour + minute/60`) — the now-line
    /// position. Derived live from `tl.date`.
    private func fractionalHour(_ date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
    }

    /// Thin call-through to the unit-covered free-time gap math.
    private func freeTimeLabel(nowFrac: Double) -> (text: String, midFrac: Double)? {
        TodayDashboard.embeddedFreeTimeLabel(
            nowFrac: nowFrac,
            blocks: blocks,
            windowStart: startH,
            windowEnd: endH
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            allDayStrip
            if blocks.isEmpty {
                railEmptyState
            } else {
                scrollingAxis
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("DAY")
                .font(Self.headerFont)
                .foregroundStyle(NexusColor.Text.tertiary)
            Text(headerDate)
                .font(Self.headerTimeFont)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
    }

    /// Pinned all-day row above the scrollable hour axis (mirrors
    /// `DayGridView.allDayBanner`); never scrolls away with the hour grid.
    @ViewBuilder
    private var allDayStrip: some View {
        if !allDay.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(allDay, id: \.id) { item in
                    HStack(spacing: 8) {
                        Text("all-day")
                            .font(Self.gridFont)
                            .foregroundStyle(NexusColor.Text.disabled)
                        Text(item.title)
                            .font(Self.blockTitleFont)
                            .foregroundStyle(NexusColor.Text.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("All day, \(item.title)")
                }
            }
            .padding(.leading, gutter)
            Rectangle()
                .fill(NexusColor.Line.hairline.opacity(0.6))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// The scrollable 0–24 hour axis: the Canvas draws the whole day at a
    /// fixed `axisHeight` (taller than the viewport) inside a `ScrollView`;
    /// per-hour anchor views let `ScrollViewReader` jump to the current hour on
    /// appear (a `Canvas` is opaque, so `scrollTo` needs real `.id`'d views).
    private var scrollingAxis: some View {
        // `TimelineView` wraps only the Canvas (not the static `hourAnchors`),
        // so the anchors/scroll structure aren't re-evaluated every tick.
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    hourAnchors
                    TimelineView(.animation(paused: reduce)) { tl in
                        timelineCanvas(now: tl.date)
                    }
                }
                .frame(height: axisHeight)
            }
            .onAppear {
                // Land on the current hour, mid-viewport. The async hop defers
                // until the ScrollView has laid out content — a synchronous
                // `scrollTo` in `onAppear` often no-ops and opens at 00:00.
                let hour = Calendar.current.component(.hour, from: Date())
                DispatchQueue.main.async {
                    proxy.scrollTo(Self.anchorID(for: hour), anchor: .center)
                }
            }
        }
    }

    /// Invisible per-hour layout anchors the `ScrollViewReader` targets — they
    /// tile the full axis so each carries its true layout position (`scrollTo`
    /// needs layout position, not a render transform; an `.offset` won't work).
    private var hourAnchors: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Color.clear
                    .frame(height: hourHeight)
                    .id(Self.anchorID(for: hour))
            }
        }
        .accessibilityHidden(true)
    }

    /// Hourly grid lines + hour labels across the full 0–24 day, stepped
    /// every 2 hours to keep the rail uncluttered.
    private func drawGrid(in ctx: inout GraphicsContext, size: CGSize) {
        for hr in stride(from: 0, through: 24, by: 2) {
            let yy = y(Double(hr))
            var line = Path()
            line.move(to: CGPoint(x: gutter, y: yy))
            line.addLine(to: CGPoint(x: size.width, y: yy))
            ctx.stroke(
                line,
                with: .color(NexusColor.Line.hairline.opacity(0.6)),
                lineWidth: 1
            )
            ctx.draw(
                Text(String(format: "%02d", hr))
                    .font(Self.gridFont)
                    .foregroundStyle(NexusColor.Text.disabled),
                at: CGPoint(x: 2, y: yy),
                anchor: .leading
            )
        }
    }

    /// Schedule block rectangles (name + time).
    private func drawBlocks(in ctx: inout GraphicsContext, size: CGSize) {
        for block in blocks {
            let top = y(block.a)
            let bh = max(20, y(block.b) - top)
            let rect = CGRect(
                x: gutter + 4,
                y: top,
                width: size.width - gutter - 4,
                height: bh
            )
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 7),
                with: .color(NexusColor.Background.controlHover)
            )
            let tick = CGRect(
                x: rect.minX, y: rect.minY + 3, width: 2, height: rect.height - 6
            )
            ctx.fill(
                Path(roundedRect: tick, cornerRadius: 1),
                with: .color(NexusColor.Text.tertiary)
            )
            ctx.draw(
                Text(block.title)
                    .font(Self.blockTitleFont)
                    .foregroundStyle(NexusColor.Text.secondary),
                at: CGPoint(x: rect.minX + 10, y: bh > 30 ? rect.minY + 11 : rect.midY),
                anchor: .leading
            )
            if bh > 30 {
                ctx.draw(
                    Text(block.time)
                        .font(Self.blockTimeFont)
                        .foregroundStyle(NexusColor.Text.muted),
                    at: CGPoint(x: rect.minX + 10, y: rect.minY + 25),
                    anchor: .leading
                )
            }
        }
    }

    /// Now-line + pulsing dot + live "HH:mm" indicator (the pulse is pinned to
    /// its resting value under Reduce Motion).
    private func drawNowLine(
        in ctx: inout GraphicsContext, size: CGSize, now: Date, nowFrac: Double
    ) {
        let pulse =
            reduce
            ? 1.0
            : 0.4 + 0.6
                * (0.5 + 0.5
                    * sin(
                        now.timeIntervalSinceReferenceDate
                            / NexusMotion.breathePeriod * 2 * .pi))
        let ny = y(nowFrac)
        var nline = Path()
        nline.move(to: CGPoint(x: gutter, y: ny))
        nline.addLine(to: CGPoint(x: size.width, y: ny))
        ctx.stroke(
            nline,
            with: .color(NexusColor.Text.primary.opacity(0.3 + 0.25 * pulse)),
            lineWidth: 1
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: gutter - 2.5, y: ny - 2.5, width: 5, height: 5)),
            with: .color(NexusColor.Text.primary.opacity(pulse))
        )
        ctx.draw(
            Text(nowLabel(now))
                .font(Self.nowFont)
                .foregroundStyle(NexusColor.Text.secondary),
            at: CGPoint(x: 2, y: ny - 11),
            anchor: .leading
        )
    }

    private func timelineCanvas(now: Date) -> some View {
        Canvas { ctx, size in
            drawGrid(in: &ctx, size: size)
            let nowFrac = fractionalHour(now)
            if let free = freeTimeLabel(nowFrac: nowFrac) {
                ctx.draw(
                    Text(free.text)
                        .font(Self.freeFont)
                        .foregroundStyle(NexusColor.Text.disabled),
                    at: CGPoint(x: gutter + 10, y: y(free.midFrac)),
                    anchor: .leading
                )
            }
            drawBlocks(in: &ctx, size: size)
            drawNowLine(in: &ctx, size: size, now: now, nowFrac: nowFrac)
        }
        // A `Canvas` is opaque to VoiceOver — replace its subtree with one
        // element per block (interleaved with the now-line). The pure helper
        // `embeddedTimelineAccessibilityLabels` is the single label source,
        // also exercised by `EmbeddedTimelineBlocksTests` to prevent drift.
        .accessibilityRepresentation {
            let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
                blocks: blocks,
                now: now
            )
            VStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(label)
                }
            }
        }
    }

    private static func anchorID(for hour: Int) -> String { "hour-\(hour)" }

    /// Today's "<weekday> <day>" subtitle (computed per body eval so it stays
    /// current across midnight) — replaces the old "9:00–20:00" window copy.
    private var headerDate: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter.string(from: Date())
    }

    /// An empty day (no timed blocks) renders a quiet placeholder instead of a
    /// bare grid. All-day items, if any, still show in the strip above.
    private var railEmptyState: some View {
        ZStack {
            // Faint hour-grid rhythm so the empty rail reads as "a clear day",
            // not an unfinished strip.
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(NexusColor.Line.hairline.opacity(0.32))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, gutter)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)

            VStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(NexusColor.Text.muted)
                Text("No blocks scheduled")
                    .font(Self.emptyTitleFont)
                    .foregroundStyle(NexusColor.Text.tertiary)
                Text("Your day is clear")
                    .font(Self.emptyBodyFont)
                    .foregroundStyle(NexusColor.Text.muted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    // Canvas-only sub-token fonts. NexusType's token sizes don't cover the
    // 9–11pt Canvas typography, and its internal font-name helpers aren't
    // visible from TasksFeature; the families are registered process-wide at
    // launch by `NexusFontRegistration.registerAll()`, so `Font.custom(...)`
    // with the registered names is the supported way to hit the exact type.
    private static let headerFont = Font.custom("IBMPlexMono-SemiBold", size: 11)
    private static let headerTimeFont = Font.custom("IBMPlexMono-Medium", size: 12)
    private static let gridFont = Font.custom("IBMPlexMono-Medium", size: 10)
    private static let freeFont = Font.custom("Inter-Regular", size: 11)
    private static let emptyTitleFont = Font.custom("Inter-Medium", size: 12)
    private static let emptyBodyFont = Font.custom("Inter-Regular", size: 11)
    private static let blockTitleFont = Font.custom("Inter-Medium", size: 12)
    private static let blockTimeFont = Font.custom("IBMPlexMono-Medium", size: 10)
    private static let nowFont = Font.custom("IBMPlexMono-SemiBold", size: 10)
}
