import NexusCore
import NexusUI
import SwiftUI

// MARK: - Embedded-Today Canvas day-timeline right rail (MP-2 slice 4)
//
// Rebuilds the embedded (Nexus shell) Today RIGHT RAIL to the accepted Lab
// `DayTimeline` oracle: 9–20 grid, schedule blocks, free-time labels, and a
// live now-line driven by `TimelineView(.animation(paused: reduce))`.
//
// COMPOSITION DECISION (explicit, reported to the user): the Lab Today
// right rail per the oracle is `DayTimeline` ONLY. The capture-pills +
// morning-digest content that previously occupied the embedded right rail
// (`rightRail` getter + `+RightRail.swift`) is therefore UNMOUNTED on the
// embedded path here to match the Lab organism. That code is RETAINED and
// UNCHANGED — the standalone (`standaloneRegularBody`) and iOS-compact
// paths still mount `rightRail` exactly as before, so this is reversible
// by flipping the one branch in `embeddedRegularBody` back to `rightRail`.
// Capture access is NOT lost: slice-1's bottom command bar + the
// `NexusTopBar` "New"/"Ask" actions still reach capture.
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
        // The rail FILLS the full height of the content area: the day grid
        // (9–20) spans top→bottom so blocks/now-line sit at their true
        // wall-clock position and the rail never reads as a short strip
        // floating in a 2/3-empty column. `EmbeddedDayTimeline` flexes to fill
        // (its Canvas/empty-state use `maxHeight: .infinity`); no trailing
        // `Spacer` is needed and none should be re-added — it would re-collapse
        // the grid back to `canvasH` at the top.
        EmbeddedDayTimeline(
            blocks: Self.embeddedTimelineBlocks(
                tasks: scheduleTasks,
                events: todaysEvents
            )
        )
        .padding(18)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
        }
        // Tokenized contained panel shadow (was a raw `.black.opacity(0.42)`
        // r22 diffuse glow — off-system; the Linear set is contained drops).
        .nexusShadow(NexusShadow.s2)
    }

    /// A single timeline block in fractional-hour coordinates, clamped to the
    /// visible 9–20 window. Pure value type — presentation geometry, not a
    /// model. `a`/`b` are start/end as `hour + minute/60`; `time` is the
    /// "HH:mm" start label.
    ///
    /// NOT `Identifiable` — the Canvas iterates the block list with a bare
    /// `for block in blocks` (no `ForEach`, no `\.id` key path anywhere), so
    /// the conformance was dead. The `id` STORED FIELD is retained: it is a
    /// `"task:<uuid>"` / `"event:<id>"` key prefix used by the builder for
    /// origin disambiguation, not for SwiftUI identity.
    struct EmbeddedTimelineBlock {
        let id: String
        let a: Double
        let b: Double
        let title: String
        /// "HH:mm" start label — same formatter as the Canvas start indicator.
        let time: String
        /// "HH:mm" end label — from the original (un-clamped) end `Date`.
        /// Used by the accessibility representation so VoiceOver reads the
        /// real end time rather than the window-clamped fractional `b`.
        let endTime: String
    }

    /// Build the Canvas blocks from EXISTING schedule data the dashboard
    /// already loaded — `scheduleTasks` (`TodayQuery.today`, set in
    /// `reloadScheduleData()` `TodayDashboard.swift:435`) and `todaysEvents`
    /// (the calendar provider, same reload). No new query/predicate/repo.
    ///
    /// A task contributes a block only if it has a real `startAt` (the same
    /// "scheduled" rule `ScheduleGrouping` uses — `startAt == nil` ⇒
    /// unscheduled, not on the timeline). Its end is `endAt ?? dueAt ??
    /// start` (identical fallback to `ScheduleItem.end` /
    /// `ScheduleGrouping`). Events use their `start`/`end` directly.
    ///
    /// Blocks whose `[start, end]` does not overlap the visible 9–20 window
    /// are dropped; partial overlaps are clamped to the window edges so the
    /// Canvas never draws outside its rect or inverts a rectangle.
    ///
    /// ALL-DAY / CROSS-MIDNIGHT LIMITATION (intentional — this is a
    /// wall-clock day view, not a duration timeline). `fractionalHour`
    /// reads ONLY `.hour` + `.minute` of the wall-clock date; it carries no
    /// day component. Consequences, all by design:
    ///   • An all-day event (`start` at 00:00) maps to `rawA == 0.0`, which
    ///     is `< windowStart` and below the synthetic-span floor, so it is
    ///     dropped by the 9–20 window guard. All-day items are not points
    ///     on a 9–20 hour rail and are correctly absent.
    ///   • A cross-midnight item (e.g. 23:30 → 01:00) reads `rawA == 23.5`,
    ///     `rawB` collapses toward the same wall-clock hour rather than
    ///     wrapping past midnight, so it too falls outside 9–20 and is
    ///     dropped. The rail shows a single day's working hours; an item
    ///     spanning the day boundary has no well-formed slab here.
    /// This is deliberately DST-correct: using wall-clock `.hour`/`.minute`
    /// (not an absolute interval) means a clock change does not skew block
    /// positions — 14:00 is always 14:00 on the rail regardless of any UTC
    /// offset shift during the day.
    static func embeddedTimelineBlocks(
        tasks: [TaskItem],
        events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> [EmbeddedTimelineBlock] {
        let windowStart = 9.0
        let windowEnd = 20.0

        func fractionalHour(_ date: Date) -> Double {
            let comps = calendar.dateComponents([.hour, .minute], from: date)
            return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        }

        func clampedBlock(
            id: String,
            start: Date,
            end: Date,
            title: String
        ) -> EmbeddedTimelineBlock? {
            let rawA = fractionalHour(start)
            // A zero/negative-length item still gets a minimum visible slab
            // (the Canvas already enforces `max(20, …)` height); use a small
            // synthetic span so clamping math stays well-formed.
            let rawB = max(fractionalHour(end), rawA + 0.25)
            guard rawB > windowStart, rawA < windowEnd else { return nil }
            let a = max(rawA, windowStart)
            let b = min(rawB, windowEnd)
            guard b > a else { return nil }
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

        for task in tasks where task.deletedAt == nil {
            guard let start = task.startAt else { continue }
            let end = task.endAt ?? task.dueAt ?? start
            if let block = clampedBlock(
                id: "task:\(task.id.uuidString)",
                start: start,
                end: end,
                title: task.title
            ) {
                blocks.append(block)
            }
        }

        for event in events {
            if let block = clampedBlock(
                id: "event:\(event.id)",
                start: event.start,
                end: event.end,
                title: event.title
            ) {
                blocks.append(block)
            }
        }

        return blocks.sorted { $0.a < $1.a }
    }

    static let embeddedTimelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Polish free-time label for the gap between `nowFrac` and the next
    /// block strictly after it (the earliest block with `a > gapStart`), or
    /// `nil` to omit the label. Both gap bounds are clamped to the visible
    /// `[windowStart, windowEnd]` window so a far-off block does not report
    /// a misleadingly large gap, and a `nowFrac` past the window end yields
    /// no label. The threshold is `>= 30` minutes: a gap shorter than that
    /// is suppressed (not worth surfacing as "free time"); `>= 30` with
    /// `< 60` minutes renders `"wolne · Nm"`, `>= 60` renders
    /// `"wolne · Hh Mm"`.
    ///
    /// Lifted out of `EmbeddedDayTimeline` to `internal static` (NOT
    /// `public` — §5 MP-1 API freeze) purely so the anchor's free-time gap
    /// math is unit-coverable before MP-2.2 locks the pattern. Pure
    /// function — no view state, no `self`.
    static func embeddedFreeTimeLabel(
        nowFrac: Double,
        blocks: [EmbeddedTimelineBlock],
        windowStart: Double = 9.0,
        windowEnd: Double = 20.0
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

    /// Build the ordered list of VoiceOver label strings for the embedded
    /// day-timeline Canvas — one string per schedule block, plus a now-line
    /// element when `now` falls within the visible `[windowStart, windowEnd]`
    /// window. Elements are interleaved chronologically (natural swipe-through
    /// order), with the now element inserted at its wall-clock position.
    ///
    /// Format:
    ///   • Schedule block  → `"<title>, <start>–<end>"` (`endTime` is the
    ///     real un-clamped end time from the original `Date`, not the
    ///     window-clamped fractional `b`).
    ///   • Now-line        → `"Now, <HH:mm>"`.
    ///
    /// Pure function — no view state, no side effects, deterministic on
    /// `calendar`. The same seam pattern as `embeddedFreeTimeLabel`.
    ///
    /// Called from both the view's `.accessibilityRepresentation` and the
    /// test suite — single source, no parallel logic.
    static func embeddedTimelineAccessibilityLabels(
        blocks: [EmbeddedTimelineBlock],
        now: Date,
        windowStart: Double = 9.0,
        windowEnd: Double = 20.0,
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

// MARK: - DayTimeline Canvas (Today-specific; oracle parity)

/// The `Nexus*`/token equivalent of the Lab `DayTimeline` oracle
/// (`TodayHUDPreview.swift` `DayTimeline`). Presentation-pure: takes the
/// pre-derived block list and renders the 9–20 Canvas. The now-line +
/// current-time + free-time are recomputed from `tl.date` inside the
/// `TimelineView` closure so they stay live without any persisted state.
/// `private` — mirrors the oracle's `private struct DayTimeline`; zero
/// `public`, never API.
private struct EmbeddedDayTimeline: View {
    let blocks: [TodayDashboard.EmbeddedTimelineBlock]

    private let startH = 9.0
    private let endH = 20.0
    private let canvasH: CGFloat = 300
    private let gutter: CGFloat = 26

    // Reduce-Motion gated AT SOURCE: the `paused:` argument below freezes
    // the `TimelineView` schedule entirely. `reduce` is also read inside
    // the Canvas to pin the pulse to its resting value, so the now-line is
    // a steady (non-animating) line under Reduce Motion — never a call-site
    // `if reduceMotion { … }` around the construct.
    @Environment(\.accessibilityReduceMotion) private var reduce

    private func y(_ t: Double, _ height: CGFloat) -> CGFloat {
        CGFloat((t - startH) / (endH - startH)) * height
    }

    /// "HH:mm" for `date` — the live current-time indicator label. Reuses
    /// the same formatter the block builder uses.
    private func nowLabel(_ date: Date) -> String {
        TodayDashboard.embeddedTimelineTimeFormatter.string(from: date)
    }

    /// `date` as fractional hours (`hour + minute/60`) — the now-line
    /// position. Derived live from `tl.date`; the oracle hardcodes `11.7`,
    /// the real surface computes it.
    private func fractionalHour(_ date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
    }

    /// Thin call-through to the unit-covered `TodayDashboard`-level free-time
    /// gap math. The label logic itself lives on `TodayDashboard` so it is
    /// testable as a pure function; this view just supplies its own window
    /// bounds + block list.
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
            HStack(spacing: 7) {
                Text("DAY")
                    .font(Self.headerFont)
                    .foregroundStyle(NexusColor.Text.tertiary)
                Text("9:00–20:00")
                    .font(Self.headerTimeFont)
                    .monospacedDigit()
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            // Now-line pulse construct — lifted verbatim in pattern from the
            // oracle: `TimelineView(.animation(paused: reduce))` + phase from
            // `tl.date` via `sin()`. NOT `@State` + `withAnimation` (a Canvas
            // samples its closure once per redraw; the TimelineView is what
            // drives redraws). `NexusMotion.breathePeriod` (== the oracle's
            // `LabMotion.breathePeriod`, 2.4s) is the public token; using it
            // (not a `Lab*` reference) keeps the Lab as oracle-only.
            if blocks.isEmpty {
                railEmptyState
            } else {
                TimelineView(.animation(paused: reduce)) { tl in
                    Canvas { ctx, size in
                        let height = size.height
                        let pulse =
                            reduce
                            ? 1.0
                            : 0.4 + 0.6
                                * (0.5 + 0.5
                                    * sin(
                                        tl.date.timeIntervalSinceReferenceDate
                                            / NexusMotion.breathePeriod * 2 * .pi))

                        // Hourly grid lines + hour labels (9 → 19 step 2).
                        for hr in stride(from: 9, through: 19, by: 2) {
                            let yy = y(Double(hr), height)
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

                        let nowFrac = fractionalHour(tl.date)

                        // Free-time label — gap from now to the next block.
                        if let free = freeTimeLabel(nowFrac: nowFrac) {
                            ctx.draw(
                                Text(free.text)
                                    .font(Self.freeFont)
                                    .foregroundStyle(NexusColor.Text.disabled),
                                at: CGPoint(x: gutter + 10, y: y(free.midFrac, height)),
                                anchor: .leading
                            )
                        }

                        // Schedule block rectangles (name + time).
                        for block in blocks {
                            let top = y(block.a, height)
                            let bh = max(20, y(block.b, height) - top)
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
                                x: rect.minX,
                                y: rect.minY + 3,
                                width: 2,
                                height: rect.height - 6
                            )
                            ctx.fill(
                                Path(roundedRect: tick, cornerRadius: 1),
                                with: .color(NexusColor.Text.tertiary)
                            )
                            ctx.draw(
                                Text(block.title)
                                    .font(Self.blockTitleFont)
                                    .foregroundStyle(NexusColor.Text.secondary),
                                at: CGPoint(
                                    x: rect.minX + 10,
                                    y: bh > 30 ? rect.minY + 11 : rect.midY
                                ),
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

                        // Now-line + pulsing dot + live "HH:mm" indicator.
                        let ny = y(nowFrac, height)
                        if nowFrac >= startH, nowFrac <= endH {
                            var nline = Path()
                            nline.move(to: CGPoint(x: gutter, y: ny))
                            nline.addLine(to: CGPoint(x: size.width, y: ny))
                            ctx.stroke(
                                nline,
                                with: .color(NexusColor.Text.primary.opacity(0.3 + 0.25 * pulse)),
                                lineWidth: 1
                            )
                            ctx.fill(
                                Path(
                                    ellipseIn: CGRect(
                                        x: gutter - 2.5,
                                        y: ny - 2.5,
                                        width: 5,
                                        height: 5
                                    )
                                ),
                                with: .color(NexusColor.Text.primary.opacity(pulse))
                            )
                            ctx.draw(
                                Text(nowLabel(tl.date))
                                    .font(Self.nowFont)
                                    .foregroundStyle(NexusColor.Text.secondary),
                                at: CGPoint(x: 2, y: ny - 11),
                                anchor: .leading
                            )
                        }
                    }
                    // Fill the rail's full height (was a fixed `canvasH`): the
                    // `y(_:_:)` mapping is already height-relative, so the 9–20
                    // grid, blocks and now-line stretch to the column instead of
                    // bunching into a 300pt strip with dead space below.
                    .frame(minHeight: canvasH, maxHeight: .infinity)
                    // A `Canvas` is fully opaque to VoiceOver — replace its
                    // accessibility subtree with one real element per block
                    // (chronologically interleaved with the now-line element).
                    // The pure helper `TodayDashboard.embeddedTimelineAccessibilityLabels`
                    // is the single source of the label strings; it is also
                    // called by `EmbeddedTimelineBlocksTests` to prevent drift.
                    .accessibilityRepresentation {
                        let labels = TodayDashboard.embeddedTimelineAccessibilityLabels(
                            blocks: blocks,
                            now: tl.date
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
            }
        }
    }

    /// Audit B3 (a): an empty day (no scheduled tasks/events) used to
    /// render just the faint hour grid + now-line, reading as a broken,
    /// unfinished strip. A quiet achromatic placeholder under the
    /// "DAY 9–20" header makes "nothing scheduled" legible instead, in
    /// the same muted idiom the rest of the rail uses (the grid labels and
    /// "wolne · …" free-time text are `Text.disabled`). Kept at `canvasH`
    /// so the glass card does not change height between empty and populated.
    private var railEmptyState: some View {
        ZStack {
            // Faint hour grid spread across the FULL rail height — the same 9–20
            // rhythm a populated rail shows, so the empty rail reads as "a clear
            // day", not an unfinished strip.
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

            // Placeholder copy CENTERED in the full height (was pinned ~84pt
            // from the top, which floated awkwardly once the rail fills).
            VStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(NexusColor.Text.muted)
                Text("No blocks scheduled")
                    .font(Self.emptyTitleFont)
                    .foregroundStyle(NexusColor.Text.tertiary)
                Text("Your day is clear from 9:00 to 20:00")
                    .font(Self.emptyBodyFont)
                    .foregroundStyle(NexusColor.Text.muted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: canvasH, maxHeight: .infinity)
    }

    // Canvas-only sub-token fonts. NexusType's token sizes (eyebrow 10 /
    // mono 12 / meta 12 …) don't cover the oracle's 9–11pt Canvas
    // typography, and NexusType's internal `fontName(for:)`/`monoFontName`
    // are not visible from TasksFeature. The Geist / GeistMono families ARE
    // registered process-wide at app launch by
    // `NexusFontRegistration.registerAll()`, so `Font.custom(...)` with the
    // registered family names is the supported way to hit the oracle's
    // exact Canvas type — this is not bypassing the token system, it is the
    // same mechanism `NexusType` itself uses internally, matched 1:1 to the
    // oracle's `DayTimeline` Canvas.
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
