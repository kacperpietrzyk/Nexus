import SwiftUI
import WidgetKit

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                overdueCount: 2,
                todayCount: 5,
                noDateCount: 1,
                firstOverdueTitle: "Reply Magda",
                firstTodayTitles: ["Sync standup", "Review PR", "Lunch"]
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (TodayWidgetEntry) -> Void) {
        Task { @MainActor in
            let entry = TodayWidgetEntry(date: .now, snapshot: SharedReader.load())
            completion(entry)
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<TodayWidgetEntry>) -> Void) {
        Task { @MainActor in
            let entry = TodayWidgetEntry(date: .now, snapshot: SharedReader.load())
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct TodayWidgetEntryView: View {
    let entry: TodayWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(entry.snapshot.overdueCount) · \(entry.snapshot.todayCount) · \(entry.snapshot.noDateCount)")
                .font(.system(size: 14, weight: .medium))
            if let first = entry.snapshot.firstOverdueTitle {
                Text(first)
                    .font(.system(size: 12))
                    .lineLimit(2)
            } else if let firstToday = entry.snapshot.firstTodayTitles.first {
                Text(firstToday)
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(entry.snapshot.overdueCount) zaległe · \(entry.snapshot.todayCount) dziś")
                .font(.system(size: 13, weight: .medium))
            ForEach(entry.snapshot.firstTodayTitles.prefix(3), id: \.self) { title in
                Text("• \(title)")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }
}

struct TodayWidget: Widget {
    let kind: String = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dziś")
        .description("Liczniki + pierwsze zaległe zadanie.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
