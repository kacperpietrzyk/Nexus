import NexusCore
import NexusUI
import SwiftUI

/// The Up Next card: today's next 1–3 calendar events, sorted by start
/// ascending. A "+N more → Calendar" row appears when more events exist.
/// Empty state collapses to a compact single line + "Open Calendar" button,
/// matching the `fixedSize(vertical:)` pattern used across Today cards.
///
/// Replaces both the old `TodayAgendaCard` (full-day timeline) and the
/// inspector's Up Next rail card — there is now exactly one calendar surface.
struct TodayUpNextCard: View {

    /// The up-to-3 events to display (already capped by `LiquidTodayModel.upNextEvents`).
    let events: [CalendarEvent]
    /// Total count of not-yet-ended today events (used for the "+N more" row).
    let totalCount: Int
    let onOpenCalendar: () -> Void

    var body: some View {
        TodayGlassCard("Up Next") {
            if events.isEmpty {
                // Compact empty state: hug content so the card collapses to a
                // single row instead of stretching to match adjacent columns.
                LiquidEmptyState(
                    systemImage: "calendar",
                    message: "Nothing on the calendar today"
                ) {
                    LiquidPrimaryButton("Open Calendar", action: onOpenCalendar)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(events, id: \.id) { event in
                        eventRow(event)
                    }
                    if totalCount > events.count {
                        moreRow(count: totalCount - events.count)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Circle()
                .fill(DS.ColorToken.accentPrimary)
                .frame(width: 5, height: 5)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(2)
                Text(timeRange(for: event))
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }

    private func moreRow(count: Int) -> some View {
        Button(action: onOpenCalendar) {
            Text("+\(count) more \u{2192} Calendar")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.accentPrimaryHover)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Calendar to see \(count) more events")
    }

    private func timeRange(for event: CalendarEvent) -> String {
        "\(Self.timeFormatter.string(from: event.start)) – \(Self.timeFormatter.string(from: event.end))"
    }

    /// English UI rule: explicit en_US (system locale may differ).
    /// Shared via `TodayInspector.focusContextLine` which formats times too.
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
