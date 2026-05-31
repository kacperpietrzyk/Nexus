import SwiftUI

public struct NexusAvatar: View {
    public let name: String
    public let size: CGFloat

    public init(name: String, size: CGFloat = 22) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        Text(initials)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(width: size, height: size)
            .background(backgroundColor, in: Circle())
            .overlay(Circle().strokeBorder(NexusColor.Line.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
            .accessibilityLabel(name.isEmpty ? "Avatar" : name)
            .accessibilityHidden(name.isEmpty)
    }

    internal var initials: String {
        let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let value = parts.compactMap { $0.first?.uppercased() }.joined()
        return value.isEmpty ? "?" : value
    }

    private var fontSize: CGFloat {
        max(9, size * 0.42)
    }

    internal var textColor: Color {
        NexusColor.Text.primary
    }

    internal var backgroundColor: Color {
        NexusColor.Text.muted
    }
}

#Preview {
    HStack(spacing: 12) {
        NexusAvatar(name: "Maya Chen", size: 18)
        NexusAvatar(name: "Jules Park")
        NexusAvatar(name: "Nexus", size: 28)
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
