import NexusUI
import SwiftUI

struct WatchNotificationView: View {
    let title: String
    let dueAt: Date
    let projectName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NexusType.h3)
                .lineLimit(2)
                .foregroundStyle(NexusColor.Text.primary)
            Text(relativeDueText)
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.tertiary)
            if let projectName {
                Text(projectName)
                    .nexusType(NexusType.Metrics.eyebrow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(NexusColor.Background.control)
                    )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.Background.base)
    }

    private var relativeDueText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: dueAt, relativeTo: Date())
    }
}
