import SwiftUI

public struct NexusShadowProfile: Equatable, Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

public enum NexusShadow {
    public static let s1 = NexusShadowProfile(color: .black.opacity(0.30), radius: 2, y: 1)
    public static let s2 = NexusShadowProfile(color: .black.opacity(0.55), radius: 28, y: 8)
    public static let pop = NexusShadowProfile(color: .black.opacity(0.65), radius: 48, y: 16)
    public static let glass = NexusShadowProfile(color: .black.opacity(0.50), radius: 32, y: 12)
    public static let accentGlow = NexusShadowProfile(
        color: NexusColor.Text.primary.opacity(0.45),
        radius: 14,
        y: 4
    )
}

extension View {
    public func nexusShadow(_ profile: NexusShadowProfile) -> some View {
        self.shadow(color: profile.color, radius: profile.radius, x: profile.x, y: profile.y)
    }
}
