import SwiftUI

/// Timeline row with a fixed mono timestamp gutter and optional current-time rail.
public struct NexusTimeRow<Content: View>: View {
    public let timeLabel: String
    public let isCurrent: Bool
    @ViewBuilder public let content: () -> Content

    public init(
        _ timeLabel: String,
        isCurrent: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.timeLabel = timeLabel
        self.isCurrent = isCurrent
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeLabel)
                .font(NexusType.metaMono)
                .foregroundStyle(isCurrent ? NexusColor.Text.primary : NexusColor.Text.secondary)
                .frame(width: Self.gutterWidth, alignment: .trailing)
                .padding(.top, 2)

            ZStack(alignment: .topLeading) {
                if isCurrent {
                    currentRail
                }

                content()
            }
            .padding(.bottom, 12)
        }
    }

    internal static var gutterWidth: CGFloat { 48 }

    private var currentRail: some View {
        Rectangle()
            .fill(NexusColor.Accent.lime)
            .frame(height: 1)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(NexusColor.Accent.lime)
                    .frame(width: 7, height: 7)
                    .offset(x: -4, y: -3)
            }
            .padding(.top, 6)
            .padding(.leading, -6)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        NexusTimeRow("09:30") {
            NexusCard(padding: 14) {
                Text("Planning")
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
        NexusTimeRow("10:00", isCurrent: true) {
            NexusCard(padding: 14) {
                Text("Focus block")
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
