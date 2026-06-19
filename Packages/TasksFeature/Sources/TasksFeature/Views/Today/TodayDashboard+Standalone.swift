import NexusCore
import NexusUI
import SwiftUI

// MARK: - Standalone / iOS-compact Today body

// Houses the standalone-shell (sidebar + main column + right rail) and
// iOS-compact bodies plus their greeting+day-progress+schedule
// `todayContent`. Split out of `TodayDashboard.swift` purely for
// `file_length` headroom — symmetric with the `+EmbeddedToday.swift`
// sibling MP-2 slice 2 introduced. No logic change: every member moved
// here verbatim from the main file, keeping the same access level so the
// standalone (`standaloneRegularBody`) and iOS-compact (`compactBody`)
// paths render identically. The embedded path stays in +EmbeddedToday.

extension TodayDashboard {

    var standaloneRegularBody: some View {
        HStack(spacing: 0) {
            if showsNavigationRail {
                SidebarView(
                    selection: activeSelection,
                    taskFilter: taskFilter,
                    inboxUnreadCount: inboxUnreadCount,
                    taskFilterTitle: taskFilterTitle,
                    onOpenCapture: onOpenCapture
                )
            }
            mainColumn
            rightRail
                .frame(width: 320)
        }
    }

    // MP-5.1a iOS Today RE-ROUTE: iPhone-compact now renders the
    // MP-2-migrated `embeddedTodayContent` status-sectioned organism — the
    // `IOSTodayPreview` oracle idiom (NOW NowCard + TODAY / AWAITING YOU
    // / LATER sections) — replacing the legacy greeting + day-progress +
    // schedule `todayContent` (which stays untouched: it is still the
    // `.standalone` content router's iPad/regular path at
    // `TodayDashboard.swift:318`). `embeddedTodayContent` is REUSED by
    // reference, not duplicated — same view, same already-loaded feed
    // (`reloadScheduleData()` populates `embeddedTodayTasks`/
    // `embeddedAwaiting`/`embeddedLaterTasks` on every path, including this
    // compact one), and ZERO shared-code modification: editing the shared
    // organism in `+EmbeddedToday.swift` would regress the MP-2-CLOSED Mac
    // embedded path. Per §1-host-frozen + storyboard-is-Lab-device: the iOS
    // Lab oracles ship full screen-level mockups including their own chrome;
    // the production `NavigationStack` `.navigationTitle("Today")` (in
    // `TodayTab.swift`, not this file) IS the retained host chrome, so the
    // oracle's in-content header (Today/date/synced) is Lab-screen-mockup
    // chrome and is NOT rebuilt as a second in-content header (date/synced
    // are §10-omit-as-redundant), and the oracle's floating bottom capsule
    // is Lab-device chrome — the production iOS `TabView` tab bar is the
    // real shell bar, so NO floating bottom bar is added. The existing `+`
    // capture FAB is the production capture affordance — RETAINED
    // byte-unchanged. The bottom safe-area inset replaces the old inline
    // `Spacer(84)`: it keeps the `+` FAB / iOS tab bar from occluding the
    // last row, applied here at the compact composition root (a wrapper
    // modifier on the organism's own inner `ScrollView`) without touching
    // shared code.
    var compactBody: some View {
        ZStack(alignment: .bottomTrailing) {
            embeddedTodayContent
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 84)
                }

            if showsCompactCaptureFAB {
                Button {
                    onOpenCapture(.task)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(NexusColor.Text.primary)
                        .frame(width: 56, height: 56)
                        .background(NexusColor.Background.controlHover, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 24)
                .accessibilityLabel("Capture task")
            }
        }
    }

    var todayContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            let now = Date.now
            let schedule = ScheduleGrouping.group(
                tasks: scheduleTasks,
                events: todaysEvents,
                blocks: scheduleBlocks,
                now: now
            )
            let activeTasks = scheduleTasks.filter { $0.deletedAt == nil }
            let summary = Self.dayProgressSummary(tasks: activeTasks)

            greetingBlock(
                now: now,
                workspaceName: Self.resolvedWorkspaceName(stored: workspaceDisplayName),
                meetingsCount: todaysEvents.count,
                tasksCount: summary.totalCount,
                focusBlockTime: Self.focusBlockTime(now: now, tasks: activeTasks)
            )

            dayProgress(
                now: now,
                items: summary.progressItems,
                doneCount: summary.doneCount,
                totalCount: summary.totalCount,
                focusedMinutes: summary.focusedMinutes
            )

            scheduleTimeline(slots: schedule.slots, unscheduled: schedule.unscheduled, now: now)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}
