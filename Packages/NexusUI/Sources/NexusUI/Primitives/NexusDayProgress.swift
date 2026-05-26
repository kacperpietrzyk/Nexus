import SwiftUI

/// Compact day progress rail for v4 timeline surfaces.
public struct NexusDayProgress: View {
    public let progress: Double
    public let tickFractions: [Double]
    public let doneCount: Int
    public let totalCount: Int
    public let focusedMinutes: Int

    public init(
        progress: Double,
        tickFractions: [Double] = [],
        doneCount: Int = 0,
        totalCount: Int = 0,
        focusedMinutes: Int = 0
    ) {
        self.progress = Self.clamp(progress)
        self.tickFractions = tickFractions.map(Self.clamp)
        self.doneCount = doneCount
        self.totalCount = totalCount
        self.focusedMinutes = focusedMinutes
    }

    public var body: some View {
        NexusCard(.elev1, padding: 0) {
            HStack(spacing: 14) {
                Text("DAY")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                GeometryReader { geometry in
                    rail(width: geometry.size.width)
                }
                .frame(height: 20)

                Text(doneCaption)
                    .font(NexusType.mono)
                    .foregroundStyle(NexusColor.Text.secondary)

                Text(focusedCaption)
                    .font(NexusType.mono)
                    .foregroundStyle(NexusColor.Text.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    internal var doneCaption: String {
        "\(doneCount)/\(totalCount) done"
    }

    internal var focusedCaption: String {
        "\(focusedMinutes / 60)h \(focusedMinutes % 60)m focused"
    }

    internal static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func rail(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(NexusColor.Background.control)
                .frame(height: 6)

            Capsule()
                .fill(NexusColor.Text.primary)
                .frame(width: max(0, width * progress), height: 6)

            ForEach(Array(tickFractions.enumerated()), id: \.offset) { _, fraction in
                Rectangle()
                    .fill(NexusColor.Background.panel)
                    .frame(width: 2, height: 12)
                    .offset(x: max(0, width * fraction - 1), y: -3)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(NexusColor.Text.primary)
                .frame(width: 11, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(NexusColor.Background.panel, lineWidth: 2)
                )
                .offset(x: max(0, width * progress - 5.5), y: -7)
        }
        .frame(height: 6)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

#Preview {
    NexusDayProgress(
        progress: 0.42,
        tickFractions: [0.12, 0.34, 0.66],
        doneCount: 3,
        totalCount: 12,
        focusedMinutes: 138
    )
    .padding(40)
    .background(NexusColor.Background.base)
}
