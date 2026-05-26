import SwiftUI
import WidgetKit

struct TodayRectangularEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchComplicationSnapshot
}

struct TodayRectangularProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayRectangularEntry {
        TodayRectangularEntry(
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

    func getSnapshot(in _: Context, completion: @escaping @Sendable (TodayRectangularEntry) -> Void) {
        Task { @MainActor in
            completion(TodayRectangularEntry(date: .now, snapshot: SharedReader.load()))
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<TodayRectangularEntry>) -> Void) {
        Task { @MainActor in
            let entry = TodayRectangularEntry(date: .now, snapshot: SharedReader.load())
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct TodayRectangularView: View {
    let entry: TodayRectangularEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headline)
                .font(.system(size: 12, weight: .semibold))
            if let title = entry.snapshot.firstUpcomingTitle, let due = entry.snapshot.firstUpcomingDueAt {
                Text("\(due, format: .dateTime.hour().minute()) \(title)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nic w kalendarzu")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        if entry.snapshot.overdueCount > 0 {
            return "\(entry.snapshot.overdueCount) overdue · \(entry.snapshot.todayCount) dziś"
        }
        return "\(entry.snapshot.todayCount) dziś"
    }
}

struct TodayRectangularComplication: Widget {
    let kind = "TodayRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayRectangularProvider()) { entry in
            TodayRectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "nexus://today"))
        }
        .configurationDisplayName("Dziś - podsumowanie")
        .description("Liczba zadań i najbliższy termin")
        .supportedFamilies([.accessoryRectangular])
    }
}
