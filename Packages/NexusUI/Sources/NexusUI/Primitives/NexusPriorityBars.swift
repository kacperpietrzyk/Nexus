import SwiftUI

public enum NexusPriorityLevel: Int, CaseIterable, Sendable {
    case zero = 0
    case low = 1
    case medium = 2
    case high = 3
    case urgent
}

public struct NexusPriorityBars: View {
    public let level: NexusPriorityLevel

    public init(_ level: NexusPriorityLevel) {
        self.level = level
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { index, height in
                bar(height: height, color: barColor(index: index))
            }
        }
        .frame(height: Self.frameHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    internal var accessibilityLabel: String {
        switch level {
        case .zero: return "No priority"
        case .low: return "Low priority"
        case .medium: return "Medium priority"
        case .high: return "High priority"
        case .urgent: return "Urgent priority"
        }
    }

    internal func isFilled(index: Int) -> Bool {
        guard index >= 0, index < Self.barHeights.count else {
            return false
        }

        switch level {
        case .zero:
            return false
        case .low:
            return index < 1
        case .medium:
            return index < 2
        case .high, .urgent:
            return true
        }
    }

    /// Emphasis ink for a level's active bars. Urgent reads at full Porcelain
    /// weight; every other level settles on Light Steel. Lime is layered on top
    /// of this by ``barColor(index:)`` for the urgent crest only.
    internal var activeColor: Color {
        switch level {
        case .urgent:
            return NexusColor.Text.primary
        case .zero, .low, .medium, .high:
            return NexusColor.Text.secondary
        }
    }

    /// Index of the tallest active bar for the current level, or `nil` when no
    /// bar is filled. This crest carries the level's emphasis ink (and the lime
    /// accent for urgent); shorter active bars step down to Storm Cloud.
    internal var crestIndex: Int? {
        (0..<Self.barHeights.count).last(where: isFilled)
    }

    /// Per-bar fill. Unfilled bars dim to disabled ink; filled bars ramp from
    /// Storm Cloud (`Text.tertiary`) up to the level's ``activeColor`` at the
    /// crest, so the ascent reads as weight. The crest of the highest level
    /// (urgent) takes the single lime accent — the only saturated color this
    /// primitive may use.
    internal func barColor(index: Int) -> Color {
        guard isFilled(index: index) else {
            return NexusColor.Text.disabled
        }

        guard index == crestIndex else {
            return NexusColor.Text.tertiary
        }

        return level == .urgent ? NexusColor.Accent.lime : activeColor
    }

    internal static let barWidth: CGFloat = 2.5
    internal static let spacing: CGFloat = 1.5
    internal static let frameHeight: CGFloat = 12
    internal static let barHeights: [CGFloat] = [4, 8, 12]

    private func bar(height: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: Self.barWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(NexusPriorityLevel.allCases, id: \.self) { level in
            NexusPriorityBars(level)
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
