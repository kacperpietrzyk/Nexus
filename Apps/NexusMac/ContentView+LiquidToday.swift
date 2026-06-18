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
            decisionsProvider: { fetchTodayDecisions() },
            briefProvider: dailyBriefProvider,
            // Focus Suggestion seam: CalendarFeature's scheduling intelligence,
            // injected so TasksFeature stays decoupled. The model computes and
            // stores the gap during reload; the inspector renders the result.
            focusGapProvider: { events, window in
                SchedulingIntelligence.suggestedFocusBlocks(events: events, within: window)
            },
            // macOS shows the title+date in the toolbar band (LiquidTodayTitle),
            // so the in-content header is hidden and the cards start higher,
            // aligning with the right Daily Brief rail.
            showsInlineHeader: false,
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

    /// Fetches recent processed meetings and builds the flat decisions feed for the
    /// Today Decisions card. Decisions are parsed HERE (app layer) so TasksFeature
    /// never imports NexusMeetings.
    @MainActor
    private func fetchTodayDecisions() -> [LiquidTodayDecision] {
        // Fetch recent-processed meetings (startedAt desc, capped at 10).
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.processedAt != nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let meetings = (try? modelContext.fetch(descriptor)) ?? []

        let rows = meetings.map { meeting in
            LiquidTodayMeetingDecisions(
                meetingID: meeting.id,
                meetingTitle: meeting.title,
                meetingDate: meeting.startedAt,
                decisions: MeetingSummarySections.parse(summaryText: meeting.summaryText).decisions
            )
        }
        return LiquidTodayModel.aggregateDecisions(rows, cap: 5)
    }
}
