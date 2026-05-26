import NexusCore
import SwiftUI
import WidgetKit

struct TodayCircularEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchComplicationSnapshot
}

struct TodayCircularProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayCircularEntry {
        TodayCircularEntry(
            date: .now,
            snapshot: WatchComplicationSnapshot(
                overdueCount: 0,
                todayCount: 0,
                firstUpcomingTitle: nil,
                firstUpcomingDueAt: nil,
                firstUpcomingPriority: nil
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (TodayCircularEntry) -> Void) {
        Task { @MainActor in
            completion(TodayCircularEntry(date: .now, snapshot: SharedReader.load()))
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<TodayCircularEntry>) -> Void) {
        Task { @MainActor in
            let entry = TodayCircularEntry(date: .now, snapshot: SharedReader.load())
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct TodayCircularView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TodayCircularEntry

    private var totalCount: Int {
        entry.snapshot.overdueCount + entry.snapshot.todayCount
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: entry.snapshot.overdueCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
        case .accessoryCorner:
            Text("\(totalCount)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel {
                    Label(cornerLabel, systemImage: entry.snapshot.overdueCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
                }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(totalCount)")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(priorityColor)
                    Text(entry.snapshot.overdueCount > 0 ? "late" : "dziś")
                        .font(.system(size: 9, weight: .medium))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inlineText: String {
        if entry.snapshot.overdueCount > 0 {
            return "\(entry.snapshot.overdueCount) overdue"
        }
        if totalCount == 0 {
            return "Nexus clear"
        }
        return "\(totalCount) today"
    }

    private var cornerLabel: String {
        entry.snapshot.overdueCount > 0 ? "late" : "today"
    }

    private var priorityColor: Color {
        if entry.snapshot.overdueCount > 0 {
            return .red
        }
        switch entry.snapshot.firstUpcomingPriority ?? .none {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .none: return .primary
        }
    }
}

struct TodayCircularComplication: Widget {
    let kind = "TodayCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayCircularProvider()) { entry in
            TodayCircularView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "nexus://today"))
        }
        .configurationDisplayName("Dziś - liczba")
        .description("Liczba zadań na dziś")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
