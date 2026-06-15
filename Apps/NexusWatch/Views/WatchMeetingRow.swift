import NexusCore
import NexusUI
import SwiftUI

/// A single cached meeting glance row: title, summary snippet, and an
/// action-item count badge. Read-only — the Watch is a glance device.
struct WatchMeetingRow: View {
    let glance: WatchMeetingGlance

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(glance.title.isEmpty ? "Untitled" : glance.title)
                    .font(.headline)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if glance.actionItemCount > 0 {
                    Label("\(glance.actionItemCount)", systemImage: "checklist")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .foregroundStyle(NexusColor.Text.secondary)
                }
            }
            if !glance.summarySnippet.isEmpty {
                Text(glance.summarySnippet)
                    .font(.caption2)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)
            }
        }
    }
}
