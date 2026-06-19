import InboxShell
import NexusAgent
import NexusCore
import SwiftData
import SwiftUI

// Activity-feed wiring for the Mac shell, extracted from `ContentView` to keep
// its struct body under the lint budget. Registers the app-owned DailyBrief
// projector + the state provider into `FeedRegistry`, recomputes the sidebar
// unread badge, routes opened rows, and persists per-row state transitions.
// Module-owned projectors register from their own roots (Unscheduled via
// `TasksComposition.bootstrap`, Meeting via `MeetingsComposition.registerInboxSource`).
extension ContentView {

    /// Registers the app-owned activity-feed projector (DailyBrief) and the
    /// state provider into `FeedRegistry`. `container` is the Sendable
    /// `ModelContainer` captured at the call site so the `@Sendable` closures
    /// stay legal under strict concurrency.
    @MainActor
    func bootstrapActivityFeed(container: ModelContainer) async {
        await FeedRegistry.shared.register(
            DailyBriefProjector(
                dayKeyProvider: { DailyBriefProjector.dayKey(for: Date()) },
                snapshotProvider: {
                    try await MainActor.run {
                        let writer = AgentBriefDailyNoteWriter(modelContext: container.mainContext)
                        let request = AgentBriefRequest(
                            counts: AgentBriefCounts(overdue: 0, today: 0, noDate: 0, awaiting: 0),
                            firstTitles: [],
                            now: Date()
                        )
                        guard let snapshot = try writer.todayDailyNote(for: request) else { return nil }
                        return (text: snapshot.plainText, updatedAt: snapshot.updatedAt)
                    }
                }
            )
        )
        await FeedRegistry.shared.setStateProvider {
            await MainActor.run {
                let states = (try? FeedItemStateRepository(context: container.mainContext).all()) ?? [:]
                return states.mapValues {
                    FeedRegistry.State(
                        seenAt: $0.seenAt,
                        dismissedAt: $0.dismissedAt,
                        snoozedUntil: $0.snoozedUntil
                    )
                }
            }
        }
    }

    /// The sidebar badge is the activity-feed UNREAD count (visible, unseen,
    /// non-bridge). `FeedRegistry` caches the projected set and self-invalidates
    /// on store change, so this is cheap to recompute.
    @MainActor
    func reloadInboxCount() async {
        inboxUnreadCount = (try? await FeedRegistry.shared.unreadCount(now: Date())) ?? 0
    }

    /// Routes an opened activity-feed row to its destination. Module-level
    /// navigation only — deep-linking is refined in Plan 2.
    @MainActor
    func openInboxItem(_ item: FeedItem) {
        switch item.route {
        case .meeting(let id):
            // Hand the meeting id to the shared meeting-nav router (the same seam
            // `observeMeetingNavigation` consumes to switch to the Meetings
            // surface); falls back to opening the module if no router is wired.
            if let router = meetingNavigationRouter {
                router.navigate(to: id)
            } else {
                navigate(to: .meetings)
            }
        case .dailyBrief:
            navigate(to: .today)
        case .unscheduledTasks:
            // TODO(Plan 2): preselect TaskFilter.inbox ("Unscheduled") — the
            // filter lives in TodayDashboard's own @State, so the shell can only
            // route to the Tasks surface today.
            navigate(to: .tasks)
        case .agentInsight:
            // TODO(Plan 2): deep-link to the specific insight.
            navigate(to: .agent)
        }
        markFeedItemSeen(item)
    }

    /// Persist a feed-item state transition via `FeedItemStateRepository`; the
    /// repository owns the single `context.save()`.
    @MainActor
    func markFeedItemSeen(_ item: FeedItem) {
        try? FeedItemStateRepository(context: modelContext).upsert(key: item.key) {
            $0.seenAt = Date()
        }
    }

    @MainActor
    func dismissFeedItem(_ item: FeedItem) {
        try? FeedItemStateRepository(context: modelContext).upsert(key: item.key) {
            $0.dismissedAt = Date()
        }
    }

    @MainActor
    func snoozeFeedItem(_ item: FeedItem, until date: Date) {
        try? FeedItemStateRepository(context: modelContext).upsert(key: item.key) {
            $0.snoozedUntil = date
        }
    }
}
