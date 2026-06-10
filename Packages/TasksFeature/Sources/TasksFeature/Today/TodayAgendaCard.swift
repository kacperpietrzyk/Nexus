import NexusCore
import NexusUI
import SwiftUI

/// Spec `docs/05_MODULE_TODAY.md` §Agenda: "timeline line: 1 pt, blue/purple
/// 60% opacity" — the primary accent at 60% is the closest DS color (no
/// dedicated timeline token exists).
private let timelineLineColor = DS.ColorToken.accentPrimary.opacity(0.6)
/// Spec §Agenda: "row event height: 46–58 pt" — lower bound, rows grow with
/// a subtitle.
private let agendaRowMinHeight: CGFloat = 46
/// Width reserved for the leading "9:00 AM" labels so the timeline rail and
/// event blocks share one left edge (11 pt labels fit comfortably).
private let timeLabelWidth: CGFloat = 56

/// `Today's Agenda` card (spec §Main top row 1): a vertical timeline of
/// today's calendar events + accepted Motion-AI blocks. Time labels left
/// (11 pt tertiary), a 1 pt timeline hairline with kind-tinted dots, and
/// `LiquidAgendaBlock` rows tinted by event kind. Scrolls to the current /
/// next item by default.
struct TodayAgendaCard: View {

    let items: [LiquidAgendaItem]
    let now: Date
    let onOpenCalendar: () -> Void

    var body: some View {
        LiquidGlassCard("Today's Agenda") {
            if items.isEmpty {
                LiquidEmptyState(
                    systemImage: "calendar",
                    message: "Nothing on the calendar today."
                ) {
                    LiquidPrimaryButton("Open Calendar", action: onOpenCalendar)
                }
                .frame(maxHeight: .infinity)
            } else {
                timeline
            }
        } trailing: {
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(items) { item in
                        agendaRow(item)
                            .id(item.id)
                    }
                }
                // The timeline hairline runs behind the dot column for the
                // whole list height (spec §Agenda: 1 pt line).
                .background(alignment: .leading) {
                    Rectangle()
                        .fill(timelineLineColor)
                        .frame(width: 1)
                        .padding(.leading, timeLabelWidth + DS.Space.s + 2)
                }
            }
            .frame(maxHeight: .infinity)
            .onAppear {
                if let target = defaultScrollTarget {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// Default scroll position: the current or next item (the "8AM → now"
    /// sensible default); falls back to the last item late in the day.
    private var defaultScrollTarget: String? {
        items.first(where: { !$0.isAllDay && $0.end > now })?.id ?? items.last?.id
    }

    private func agendaRow(_ item: LiquidAgendaItem) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Text(item.isAllDay ? "All day" : Self.timeFormatter.string(from: item.start))
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .monospacedDigit()
                .frame(width: timeLabelWidth, alignment: .leading)
                .padding(.top, DS.Space.s)

            // Timeline dot, tinted by event kind, sitting on the hairline.
            Circle()
                .fill(item.kind.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 14)
                .accessibilityHidden(true)

            LiquidAgendaBlock(item.title, subtitle: subtitle(for: item), kind: item.kind)
        }
        .frame(minHeight: agendaRowMinHeight, alignment: .top)
    }

    private func subtitle(for item: LiquidAgendaItem) -> String? {
        if item.isAllDay { return item.subtitle }
        let range =
            "\(Self.timeFormatter.string(from: item.start)) – \(Self.timeFormatter.string(from: item.end))"
        guard let subtitle = item.subtitle, !subtitle.isEmpty else { return range }
        return "\(range) · \(subtitle)"
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
