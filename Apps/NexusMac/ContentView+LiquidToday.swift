import CalendarFeature
import NexusAgent
import NexusMeetings
import SwiftData
import SwiftUI
import TasksFeature

// Liquid Today / Command Center composition (Task 5), extracted out of
// `ContentView` (file-length budget) alongside the other overlay/slot
// extensions. Cross-module content for the Today screen is composed HERE —
// the same seam pattern as `meetingsContent`: meeting intelligence is fetched
// from the NexusMeetings store and the daily brief from NexusAgent's
// `AgentBriefService`, both handed across as plain values. TasksFeature
// imports neither module.
extension ContentView {

    /// The Liquid Today main column, mounted by `destinationMain` for `.today`.
    var liquidTodayMain: some View {
        LiquidTodayScreen(
            model: liquidTodayModel,
            meetingIntelProvider: { fetchTodayMeetingIntel() },
            briefProvider: dailyBriefProvider,
            // Focus Suggestion seam: CalendarFeature's scheduling intelligence,
            // injected so TasksFeature stays decoupled. The model computes and
            // stores the gap during reload; the inspector renders the result.
            focusGapProvider: { events, window in
                SchedulingIntelligence.suggestedFocusBlocks(events: events, within: window)
            },
            onNavigate: { navigate(to: $0) },
            onOpenTask: { openTask($0) },
            onOpenCapture: { mode in
                NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
            }
        )
    }

    /// Right-inspector slot content for `.today`; `nil` everywhere else so
    /// the 304 pt column disappears entirely on other destinations.
    var todayInspectorSlot: (() -> AnyView)? {
        guard selection == .today else { return nil }
        let model = liquidTodayModel
        let captureText = $todayCaptureText
        return {
            AnyView(
                TodayInspector(
                    model: model,
                    captureText: captureText,
                    onNavigate: { self.navigate(to: $0) },
                    onOpenCapture: { mode in
                        NotificationCenter.default.post(name: .nexusOpenCapture, object: mode)
                    }
                )
            )
        }
    }

    /// Adapts the existing `AgentBriefService` seam (the same service +
    /// `agentEnabled` gate the old `TodayDashboard.digestText` used) to the
    /// Liquid screen's value-typed provider. `nil` → the Daily Brief card
    /// shows its empty state instead of fabricating content.
    private var dailyBriefProvider: LiquidTodayBriefProvider? {
        guard agentEnabled, let agentBriefService else { return nil }
        return { input in
            await agentBriefService.brief(
                for: AgentBriefRequest(
                    counts: AgentBriefCounts(
                        overdue: input.overdue,
                        today: input.today,
                        noDate: input.noDate,
                        awaiting: input.awaiting
                    ),
                    firstTitles: input.firstTitles,
                    now: input.now
                )
            )
        }
    }

    /// Most recent processed meeting (`processedAt != nil`, newest first) as a
    /// plain value for the Meeting Intelligence card. Runs on the screen's
    /// reload cadence (initial task + store changes).
    @MainActor
    private func fetchTodayMeetingIntel() -> LiquidTodayMeetingIntel? {
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.deletedAt == nil && $0.processedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let meeting = try? modelContext.fetch(descriptor).first else { return nil }
        let status = MeetingProcessingStatus(rawValue: meeting.processingStatus)
        // Decisions are parsed HERE (app layer) so TasksFeature renders plain
        // values without importing NexusMeetings; the Today card shows ≤3.
        let decisions = MeetingSummarySections.parse(summaryText: meeting.summaryText).decisions
        return LiquidTodayMeetingIntel(
            title: meeting.title,
            occurredAt: meeting.startedAt,
            durationSec: meeting.durationSec,
            summary: meeting.summaryText,
            decisions: Array(decisions.prefix(3)),
            actionItemCount: meeting.actionItemIDs.count,
            statusLabel: status == .ready ? "Processed" : (status == .failed ? "Failed" : "Processing")
        )
    }
}
