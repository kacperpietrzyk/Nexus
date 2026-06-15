import NexusCore
import NexusUI
import SwiftUI

/// Watch read-only glance over recent meetings (spec: glance device). The Watch
/// has no `Meeting` type — NexusMeetings has no watchOS platform — so this reads
/// the cached `WatchMeetingGlance` array the iPhone replied with, never blocking
/// on connectivity. Tapping a row opens a read-only detail view. On appear it
/// fires a refresh query so the cache stays current when the iPhone is reachable.
struct WatchMeetingsView: View {
    @State private var glances: [WatchMeetingGlance] = []

    var body: some View {
        Group {
            if glances.isEmpty {
                ContentUnavailableView(
                    "No meetings",
                    systemImage: "person.2.wave.2",
                    description: Text("Recent meetings from your iPhone appear here.")
                )
                .foregroundStyle(NexusColor.Text.secondary)
            } else {
                List(glances) { glance in
                    NavigationLink {
                        WatchMeetingDetailView(glance: glance)
                    } label: {
                        WatchMeetingRow(glance: glance)
                    }
                }
            }
        }
        .navigationTitle("Meetings")
        .task {
            reload()
            WatchPhoneBridge.shared.sendRecentMeetingsQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchMeetingGlancesUpdated)) { _ in
            reload()
        }
    }

    private func reload() {
        let cached = WatchMeetingGlanceStore()?.load()
        // Newest first — the iPhone sorts by `startedAt` descending, but re-sort
        // defensively in case a future producer changes order.
        glances = (cached?.meetings ?? []).sorted { $0.startedAt > $1.startedAt }
    }
}

/// Full read-only view of a single cached meeting glance on the Watch: the
/// summary snippet plus the action-item count. No editing — the Watch is a
/// glance device, deeper meeting work happens on iPhone/Mac.
struct WatchMeetingDetailView: View {
    let glance: WatchMeetingGlance

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(glance.startedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(NexusColor.Text.tertiary)
                if glance.actionItemCount > 0 {
                    Label("\(glance.actionItemCount) action items", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.secondary)
                }
                if glance.summarySnippet.isEmpty {
                    Text("No summary yet.")
                        .font(.body)
                        .foregroundStyle(NexusColor.Text.tertiary)
                } else {
                    Text(glance.summarySnippet)
                        .font(.body)
                        .foregroundStyle(NexusColor.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(glance.title.isEmpty ? "Untitled" : glance.title)
    }
}
