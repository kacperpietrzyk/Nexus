import SwiftUI

/// Flat, neutral empty-state placeholder.
///
/// A centered icon + title (+ optional message). Empty states are real states,
/// not error chrome — so this reads intentional: muted neutral ink, no lime, no
/// card border (the host provides the surface). Generous vertical breathing
/// room keeps it from looking like a layout bug.
public struct NexusEmptyState: View {

    public let systemImage: String
    public let title: String
    public let message: String?

    public init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: NexusSpacing.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(NexusColor.Text.tertiary)

            Text(title)
                .font(NexusType.body.weight(.medium))
                .foregroundStyle(NexusColor.Text.secondary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NexusSpacing.s9)
    }
}

#Preview("Empty state") {
    NexusEmptyState(
        systemImage: "tray",
        title: "Inbox is clear",
        message: "New captures land here. Press ⌘N to add one."
    )
    .padding(40)
    .background(NexusColor.Background.base)
}
