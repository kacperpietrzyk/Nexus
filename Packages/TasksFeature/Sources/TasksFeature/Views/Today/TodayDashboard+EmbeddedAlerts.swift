import NexusCore
import NexusUI
import SwiftData
import SwiftUI

// MARK: - Embedded-Today alert strips (error row + deadline-risk signal)
//
// The status strips that render above the worklist sections in
// `embeddedTodaySectioned`: the data-load error row and the forward-looking
// deadline-risk banner (spec §19.1 D1). Grouped here both because they are the
// same UI family (a thin alert above the sections) and to keep
// `+EmbeddedToday.swift` within the file-length budget. The deadline-risk
// projection (open tasks + completion history) is assembled by the NexusCore
// `DeadlineRiskProjector` so the in-app surface and the `schedule.deadline_risks`
// agent tool share one query path; calendar obstacles are fetched here over the
// horizon and degrade to `[]` without access (valid per spec §13). Pure signal,
// never an auto-action (spec §19.1: suggestive, not aggressive). Achromatic —
// every tone is a frozen `NexusColor`/`NexusType` token, mirroring
// `eveningShutdownCard`.

extension TodayDashboard {
    /// ScrollView translation of `TaskListView.errorRow`: same `.caption` +
    /// `NexusColor.Text.primary` ink (achromatic — legibility via contrast,
    /// not hue), but with explicit padding instead of the `List`-only
    /// `listRowInsets`/`listRowBackground`/`listRowSeparator` modifiers, which
    /// no-op outside a `List`.
    @ViewBuilder
    func embeddedErrorRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(NexusColor.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    /// Horizon (days) the risk projection looks ahead. Matches the
    /// `schedule.deadline_risks` agent-tool default (spec §19.1).
    static let deadlineRiskHorizonDays = 14

    /// Refresh the deadline-risk signal from the current store + calendar horizon
    /// and publish it to the banner state. Called from `reloadScheduleData` on
    /// the same triggers as the rest of the Today data (last-writer-wins; the
    /// projection is idempotent over the live store).
    @MainActor
    func refreshDeadlineRisk(now: Date) async {
        let days = Self.deadlineRiskHorizonDays
        // Obstacles across the whole horizon (not just today) so the free-time
        // math sees future events; `[]` when the feed is off or access absent.
        var events: [CalendarEvent] = []
        let prefs = UserDefaultsCalendarPreferencesStore().load()
        if calendarEventsEnabled {
            let end = now.addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
            let fetched = (try? await calendarProvider.eventsBetween(start: now, end: end)) ?? []
            // #6: deadline-risk free-time math must ignore disabled calendars too.
            events = prefs.visibleEvents(fetched)
        }
        let risks = DeadlineRiskProjector.project(
            context: modelContext,
            events: events,
            prefs: prefs,
            horizon: TimeInterval(days * 24 * 60 * 60),
            now: now,
            calendar: .current
        )
        let summary = DeadlineRiskSummary.make(from: risks)
        deadlineRiskSummary = summary
        deadlineRiskTopTask = Self.deadlineRiskTopTask(summary: summary, modelContext: modelContext)
    }

    /// Resolve the single most-urgent risk task (for the banner copy + tap
    /// target), or nil when nothing is under pressure.
    @MainActor
    static func deadlineRiskTopTask(
        summary: DeadlineRiskSummary,
        modelContext: ModelContext
    ) -> TaskItem? {
        guard let taskID = summary.mostUrgent?.taskID else { return nil }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Forward-looking deadline-risk banner (spec §19.1): one tappable strip that
    /// names the most-urgent task and when to start it. Rendered only when at
    /// least one task is `tight`/`atRisk`. Tapping opens that task.
    ///
    /// Known limitation: it lives in `embeddedTodaySectioned` (the non-empty
    /// branch). When all three Today buckets are empty the column shows the
    /// achievement empty-state instead, so a risk on an out-of-bucket future
    /// deadline is not surfaced there — widening the empty-state gate is what its
    /// documented terms warn against destabilising.
    @ViewBuilder
    func deadlineRiskBanner() -> some View {
        if deadlineRiskSummary.hasPressure {
            Button {
                if let task = deadlineRiskTopTask {
                    onOpenTask?(task)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(NexusColor.Text.secondary)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Deadline risk")
                                .font(NexusType.bodySmall.weight(.semibold))
                                .foregroundStyle(NexusColor.Text.primary)
                            NexusBadge(deadlineRiskCountLabel, tone: .muted)
                            Spacer(minLength: 0)
                        }

                        Text(deadlineRiskMessage)
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Deadline risk: \(deadlineRiskMessage)")
        }
    }

    /// "N at risk" (preferred) or "N tight" — the count chip's text.
    private var deadlineRiskCountLabel: String {
        if deadlineRiskSummary.atRiskCount > 0 {
            return "\(deadlineRiskSummary.atRiskCount) at risk"
        }
        return "\(deadlineRiskSummary.tightCount) tight"
    }

    /// "Start \"Title\" by HH:mm to stay on track" when a start time is known;
    /// otherwise a tier-appropriate fallback. Never an empty string.
    private var deadlineRiskMessage: String {
        let title = deadlineRiskTopTask?.title ?? "your most urgent task"
        if let startBy = deadlineRiskSummary.mostUrgent?.suggestedStartBy {
            let time = Self.digestTimeFormatter.string(from: startBy)
            return "Start \"\(title)\" by \(time) to stay on track."
        }
        let atRisk = deadlineRiskSummary.mostUrgent?.severity == .atRisk
        return atRisk
            ? "\"\(title)\" is projected to miss its deadline."
            : "\"\(title)\" has little slack before its deadline."
    }
}
