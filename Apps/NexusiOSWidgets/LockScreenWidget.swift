import SwiftUI
import WidgetKit

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct LockScreenProvider: TimelineProvider {
    func placeholder(in _: Context) -> LockScreenEntry {
        LockScreenEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                overdueCount: 3,
                todayCount: 5,
                noDateCount: 0,
                firstOverdueTitle: "Reply Magda",
                firstTodayTitles: ["Standup", "PR review"]
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (LockScreenEntry) -> Void) {
        Task { @MainActor in
            let entry = LockScreenEntry(date: .now, snapshot: SharedReader.load())
            completion(entry)
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<LockScreenEntry>) -> Void) {
        Task { @MainActor in
            let entry = LockScreenEntry(date: .now, snapshot: SharedReader.load())
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct LockScreenEntryView: View {
    let entry: LockScreenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let first = entry.snapshot.firstTodayTitles.first {
                Text(first)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Text("\(entry.snapshot.overdueCount) overdue · \(entry.snapshot.todayCount) today")
                .font(.system(size: 10))
        }
    }
}

struct LockScreenWidget: Widget {
    let kind: String = "LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            LockScreenEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today (Lock Screen)")
        .description("First title + compact counts.")
        .supportedFamilies([.accessoryRectangular])
    }
}
