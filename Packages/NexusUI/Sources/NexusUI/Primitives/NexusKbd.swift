import SwiftUI

/// Keyboard shortcut indicator — flat Linear key cap.
public struct NexusKbd: View {
    internal static let minimumSize: CGFloat = 18
    internal static let bottomBorderHeight: CGFloat = 2
    internal static let cornerRadius: CGFloat = NexusRadius.badge

    public let key: String

    public init(_ key: String) {
        self.key = key
    }

    public var body: some View {
        Text(key)
            .font(NexusType.metaMono)
            .foregroundStyle(NexusColor.Text.tertiary)
            .frame(minWidth: Self.minimumSize, minHeight: Self.minimumSize)
            .padding(.horizontal, 5)
            .background(NexusColor.Background.controlHover, in: roundedShape)
            .overlay {
                roundedShape
                    .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
            }
    }

    /// Convenience: render a keyboard combo as a horizontal row of kbds with 4pt spacing.
    public static func combo(_ keys: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                NexusKbd(key)
            }
        }
    }

    private var roundedShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }
}

#Preview {
    HStack(spacing: 16) {
        NexusKbd("⌘")
        NexusKbd.combo(["⌘", "K"])
        NexusKbd.combo(["⌘", "⇧", "P"])
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
