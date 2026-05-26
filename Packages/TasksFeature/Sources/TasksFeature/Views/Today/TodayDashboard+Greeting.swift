import NexusCore
import NexusUI
import SwiftUI

extension TodayDashboard {
    /// Settings route placeholder. On Mac it triggers the app's Settings scene via
    /// `@Environment(\.openSettings)` (captured at the call site) and pops the selection back to
    /// `.today`. On iOS the dashboard's Settings entry is unreachable (compact uses tab shell) so
    /// this fires a notification the app shell can pick up if it ever wires the rail to compact.
    @ViewBuilder
    var settingsRoute: some View {
        #if os(macOS)
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: activeSelection.wrappedValue) {
                guard activeSelection.wrappedValue == .settings else { return }
                openSettings()
                activeSelection.wrappedValue = .today
            }
        #else
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: activeSelection.wrappedValue) {
                guard activeSelection.wrappedValue == .settings else { return }
                NotificationCenter.default.post(name: .nexusGoToSettings, object: nil)
                activeSelection.wrappedValue = .today
            }
        #endif
    }

    func greetingBlock(
        now: Date,
        workspaceName: String,
        meetingsCount: Int,
        tasksCount: Int,
        focusBlockTime: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(Self.dateLabel(for: now))
                    .font(NexusType.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)

                Rectangle()
                    .fill(NexusColor.Line.hairline)
                    .frame(width: 1, height: 10)

                Text("Week \(Self.weekLabel(for: now))")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)

                Rectangle()
                    .fill(NexusColor.Line.hairline)
                    .frame(width: 1, height: 10)

                Text(Self.timeLabel(for: now))
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.primary)
            }

            Text("\(Self.greetingPrefix(now)), \(workspaceName).")
                .font(NexusType.display)
                .foregroundStyle(NexusColor.Text.primary)

            HStack(spacing: 6) {
                Text(Self.meetingsPhrase(meetingsCount))
                Text("·")
                Text("\(tasksCount) \(tasksCount == 1 ? "task" : "tasks")")

                if let focusBlockTime {
                    Text("·")
                    Text("focus block at \(focusBlockTime)")
                        .foregroundStyle(NexusColor.Text.primary)
                }
            }
            .font(NexusType.body)
            .foregroundStyle(NexusColor.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func dayProgress(
        now: Date,
        items: [(start: Date, isDone: Bool)],
        doneCount: Int,
        totalCount: Int,
        focusedMinutes: Int
    ) -> NexusDayProgress {
        let calendar = Calendar.current
        guard
            let dayStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now),
            let dayEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
            dayEnd > dayStart
        else {
            return NexusDayProgress(
                progress: 0,
                tickFractions: [],
                doneCount: doneCount,
                totalCount: totalCount,
                focusedMinutes: focusedMinutes
            )
        }

        let duration = dayEnd.timeIntervalSince(dayStart)
        let progress = now.timeIntervalSince(dayStart) / duration
        let ticks = items.compactMap { item -> Double? in
            let fraction = item.start.timeIntervalSince(dayStart) / duration
            return (0...1).contains(fraction) ? fraction : nil
        }

        return NexusDayProgress(
            progress: progress,
            tickFractions: ticks,
            doneCount: doneCount,
            totalCount: totalCount,
            focusedMinutes: focusedMinutes
        )
    }

    /// Aggregate counts + tick fractions for the day-progress rail. Pure helper so the call site
    /// stays narrow (and `TodayDashboard.body` stays under the SwiftLint type-body cap).
    struct DayProgressSummary {
        let doneCount: Int
        let totalCount: Int
        let focusedMinutes: Int
        let progressItems: [(start: Date, isDone: Bool)]
    }

    static func dayProgressSummary(tasks: [TaskItem]) -> DayProgressSummary {
        let doneCount = tasks.filter { $0.status == .done }.count
        let totalCount = tasks.count
        let focusedMinutes = tasks.reduce(into: 0) { partial, task in
            guard let start = task.startAt, let end = task.endAt, end > start else { return }
            partial += Int(end.timeIntervalSince(start) / 60)
        }
        let progressItems = tasks.compactMap { task -> (start: Date, isDone: Bool)? in
            guard let start = task.startAt else { return nil }
            return (start: start, isDone: task.status == .done)
        }
        return DayProgressSummary(
            doneCount: doneCount,
            totalCount: totalCount,
            focusedMinutes: focusedMinutes,
            progressItems: progressItems
        )
    }

    /// Earliest future `startAt` from the supplied tasks (already filtered to "today"), formatted
    /// with the locale's short time style. Returns nil when no upcoming start exists.
    static func focusBlockTime(now: Date, tasks: [TaskItem]) -> String? {
        let upcoming = tasks.compactMap { task -> Date? in
            guard let start = task.startAt else { return nil }
            return start > now ? start : nil
        }
        guard let nextStart = upcoming.min() else { return nil }
        return focusBlockFormatter.string(from: nextStart)
    }

    /// Resolved workspace display name with deterministic fallback chain. `stored` is the value
    /// read from `@AppStorage(NexusPreferences.Keys.workspaceDisplayName)`.
    static func resolvedWorkspaceName(stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        #if canImport(AppKit)
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }
        #elseif canImport(UIKit) && !os(watchOS)
        let deviceName = UIDevice.current.name
        // iPadOS/iOS often returns "Imie iPhone" / "Kacper's iPad"; strip the trailing device
        // descriptor so the greeting reads naturally.
        let stripped = stripDeviceSuffix(deviceName)
        if !stripped.isEmpty {
            return stripped
        }
        #endif
        return "You"
    }

    #if canImport(UIKit) && !os(watchOS)
    static func stripDeviceSuffix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceSuffixes = [
            " iPhone", " iPad", " Apple Watch", " Mac",
            "'s iPhone", "'s iPad", "'s Apple Watch", "'s Mac",
            "’s iPhone", "’s iPad", "’s Apple Watch", "’s Mac",
        ]
        for suffix in deviceSuffixes where trimmed.hasSuffix(suffix) {
            let head = String(trimmed.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty {
                return head
            }
        }
        return trimmed
    }
    #endif

    private static let dateLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    private static let timeLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let focusBlockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func dateLabel(for date: Date) -> String {
        dateLabelFormatter.string(from: date).uppercased()
    }

    private static func weekLabel(for date: Date) -> String {
        String(Calendar.current.component(.weekOfYear, from: date))
    }

    static func timeLabel(for date: Date) -> String {
        timeLabelFormatter.string(from: date)
    }

    static func greetingPrefix(_ date: Date) -> String {
        switch timeOfDay(date) {
        case .morning:
            return "Good morning"
        case .afternoon:
            return "Good afternoon"
        case .evening:
            return "Good evening"
        case .night:
            return "Good night"
        }
    }

    enum TimeOfDay: Equatable {
        case morning
        case afternoon
        case evening
        case night
    }

    static func timeOfDay(_ date: Date) -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case ..<5:
            return .night
        case ..<12:
            return .morning
        case ..<18:
            return .afternoon
        case ..<22:
            return .evening
        default:
            return .night
        }
    }

    private static func meetingsPhrase(_ count: Int) -> String {
        "\(count) \(count == 1 ? "meeting" : "meetings")"
    }
}
