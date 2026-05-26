import SwiftUI

public enum NexusDotTone: CaseIterable, Equatable, Sendable {
    case acc
    case pos
    case neg
    case warn
    case info
    case muted
}

public struct NexusDotIndicator: View {
    public let tone: NexusDotTone

    public init(_ tone: NexusDotTone = .muted) {
        self.tone = tone
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: Self.side, height: Self.side)
            .overlay { ringOverlay }
            .shadow(
                color: tone == .acc ? Color.white.opacity(0.10) : .clear,
                radius: tone == .acc ? 8 : 0
            )
    }

    internal var color: Color {
        switch tone {
        case .acc:
            return NexusColor.Text.primary
        case .pos:
            return NexusColor.Text.secondary
        case .neg:
            return NexusColor.Text.primary
        case .warn:
            return NexusColor.Text.secondary
        case .info:
            return NexusColor.Text.tertiary
        case .muted:
            return NexusColor.Text.muted
        }
    }

    internal var ringColor: Color? {
        switch tone {
        case .acc:
            return Color.white.opacity(0.10)
        case .pos, .neg, .warn, .info, .muted:
            return nil
        }
    }

    @ViewBuilder private var ringOverlay: some View {
        if let ringColor {
            Circle().stroke(ringColor, lineWidth: 3)
        }
    }

    internal static let side: CGFloat = 6
}

#Preview {
    HStack(spacing: 14) {
        ForEach(NexusDotTone.allCases, id: \.self) { tone in
            NexusDotIndicator(tone)
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
