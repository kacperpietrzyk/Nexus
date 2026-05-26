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
                bar(height: height, filled: isFilled(index: index))
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

    internal var activeColor: Color {
        switch level {
        case .urgent:
            return NexusColor.Text.primary
        case .zero, .low, .medium, .high:
            return NexusColor.Text.secondary
        }
    }

    internal static let barWidth: CGFloat = 2.5
    internal static let spacing: CGFloat = 1.5
    internal static let frameHeight: CGFloat = 12
    internal static let barHeights: [CGFloat] = [4, 8, 12]

    private func bar(height: CGFloat, filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? activeColor : NexusColor.Text.disabled)
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
