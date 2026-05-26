import SwiftUI

public struct NexusAvatar: View {
    public let name: String
    public let size: CGFloat
    public let hue: Double

    public init(name: String, size: CGFloat = 22, hue: Double? = nil) {
        self.name = name
        self.size = size
        self.hue = hue ?? Self.deriveHue(from: name)
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

    internal static func deriveHue(from name: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Double(hash % 360)
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
        NexusAvatar(name: "Nexus", size: 28, hue: 240)
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
