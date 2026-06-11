import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// THE event-kind classifier for the liquid Calendar surfaces — one shared
/// mapping, mirroring exactly what the Liquid Today agenda ships
/// (`LiquidTodayModel.agendaItems` in TasksFeature hardcodes external calendar
/// events → `.meeting` and Nexus `ScheduledBlock`s → `.focus`). Feature modules
/// cannot cross-import, so the Today copy stays where it is; this is the single
/// classifier for everything inside CalendarFeature (grid, strip, inspector).
///
/// No richer kinds (project/personal/admin) are inferred: real events carry no
/// category metadata, and guessing from titles would be fabricated data.
public enum WeekEventClassifier {

    /// Kind for a grid item: external events are meetings, blocks are focus.
    public static func kind(for item: TimelineItem) -> LiquidEventKind {
        switch item.kind {
        case .event: return .meeting
        case .proposedBlock, .acceptedBlock, .seriesPreview: return .focus
        }
    }

    /// Category for the `SchedulingIntelligence` seams over raw
    /// `[CalendarEvent]`: events mirrored from accepted `ScheduledBlock`s
    /// (matched by `externalEventID`) are focus time, everything else is a
    /// meeting — the same semantics as `kind(for:)` once a block has been
    /// materialized as a mirror event in the "Nexus" calendar.
    public static func category(
        for event: CalendarEvent,
        mirroredEventIDs: Set<String>
    ) -> SchedulingIntelligence.EventCategory {
        mirroredEventIDs.contains(event.id) ? .focus : .meeting
    }

    /// Accent/fill mapping for an intelligence category (insights rows).
    public static func kind(for category: SchedulingIntelligence.EventCategory) -> LiquidEventKind {
        switch category {
        case .meeting: return .meeting
        case .focus: return .focus
        case .project: return .project
        case .personal: return .personal
        case .admin, .other: return .admin
        }
    }

    /// Display label for an intelligence category (Time Insights card).
    public static func label(for category: SchedulingIntelligence.EventCategory) -> String {
        switch category {
        case .meeting: return "Meetings"
        case .focus: return "Focus"
        case .project: return "Project work"
        case .personal: return "Personal"
        case .admin: return "Admin"
        case .other: return "Other"
        }
    }
}

/// One positioned event block on the week grid
/// (`docs/06_MODULE_CALENDAR.md` §Week grid): glass fill/stroke from the
/// `event.*` tokens by kind, 12 pt semibold title, 10–11 pt secondary time
/// line, radius 8 (`DS.Radius.s`), padding 8 (`DS.Space.s`). Hovering shows a
/// stronger stroke (§Interaction rules); clicking routes to the existing event
/// editor seam via `onTap`.
struct WeekEventBlock: View {

    let item: TimelineItem
    let height: CGFloat
    let onTap: () -> Void

    @State private var hovering = false

    /// Spec §Week grid: title 12 semibold — between the DS body (13) and
    /// metadata (11) tokens, so a commented local per the token rule.
    private static let titleFont = Font.system(size: 12, weight: .semibold)
    /// Spec §Week grid: time line 10–11 pt secondary.
    private static let timeFont = Font.system(size: 10, weight: .regular).monospacedDigit()
    /// Title (~15 pt) + time (~13 pt) + 2×8 pt padding need ≥ ~46 pt; below
    /// that only the title fits without clipping.
    private static let timeLineMinHeight: CGFloat = 46

    private var kind: LiquidEventKind { WeekEventClassifier.kind(for: item) }

    /// External events carry their EventKit calendar color (real presentation
    /// metadata, the same hue Apple Calendar shows); blocks and colorless
    /// events fall back to the kind tokens.
    private var calendarTint: LiquidCalendarTint? {
        guard item.kind == .event else { return nil }
        return LiquidCalendarTint(calendarHex: item.colorHex)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Self.titleFont)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(height >= Self.timeLineMinHeight ? 1 : 2)
                if height >= Self.timeLineMinHeight {
                    Text(timeText)
                        .font(Self.timeFont)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(DS.Space.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(calendarTint?.fill ?? kind.fill)
            }
            .overlay { strokeOverlay }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(timeText)\(item.isConflicted ? ", conflicts with a calendar event" : "")")
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }

    /// Proposed (not yet accepted) blocks keep the dashed-border affordance the
    /// existing day/week views use, so a proposal still reads as tentative.
    /// Conflicted blocks (M1) get the warning stroke regardless of kind.
    @ViewBuilder
    private var strokeOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
        let base = hovering ? DS.ColorToken.strokeStrong : (calendarTint?.stroke ?? kind.stroke)
        let color = item.isConflicted ? DS.ColorToken.statusWarning : base
        if item.kind == .proposedBlock || item.kind == .seriesPreview {
            shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(color, lineWidth: 1)
        }
    }

    private var timeText: String {
        "\(Self.timeFormatter.string(from: item.start)) – \(Self.timeFormatter.string(from: item.end))"
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
