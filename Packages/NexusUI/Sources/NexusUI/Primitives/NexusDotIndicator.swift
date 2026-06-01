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
    }

    /// Linear is flat: a clean filled dot, no glow. Lime is reserved for the
    /// single active/accent state; status tones carry semantic meaning; every
    /// other tone resolves to the neutral Fog Grey ground.
    internal var color: Color {
        switch tone {
        case .acc:
            return NexusColor.Accent.lime
        case .pos:
            return NexusColor.Status.success
        case .neg:
            return NexusColor.Status.danger
        case .info:
            return NexusColor.Status.info
        case .warn:
            return NexusColor.Text.secondary
        case .muted:
            return NexusColor.Text.muted
        }
    }

    /// Linear dots carry no ring — elevation comes from flat surfaces, not glows.
    /// Retained as `nil` for every tone so the surface reads as a clean fill.
    internal var ringColor: Color? { nil }

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
