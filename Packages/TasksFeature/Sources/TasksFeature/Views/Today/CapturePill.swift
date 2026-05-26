import NexusUI
import SwiftUI

public struct CapturePill: View {
    public let systemImage: String
    public let label: String
    public let kbdHint: String?
    public let action: () -> Void

    public init(
        systemImage: String,
        label: String,
        kbdHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.kbdHint = kbdHint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NexusColor.Text.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text(label)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)

                Spacer(minLength: 8)

                if let kbdHint {
                    NexusKbd(kbdHint)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                NexusColor.Background.raised,
                in: RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
