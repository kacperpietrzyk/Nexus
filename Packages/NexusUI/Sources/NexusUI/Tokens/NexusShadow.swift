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

/// Linear "Midnight Command Center" shadow set.
///
/// Elevation is achieved through subtle, contained drop shadows — no diffuse glows.
/// `s1` is the small card drop (--shadow-sm); `pop` is the deep-elevated overlay
/// (--shadow-xl). Intermediate tokens cover panels and floating surfaces.
public enum NexusShadow {
    /// Small drop shadow for cards and rows. Maps to Linear --shadow-sm:
    /// `rgba(0,0,0,0.4) 0 2px 4px`.
    public static let s1 = NexusShadowProfile(color: .black.opacity(0.40), radius: 2, y: 2)

    /// Medium drop shadow for panels and popovers. Sits between sm and xl.
    public static let s2 = NexusShadowProfile(color: .black.opacity(0.30), radius: 6, y: 4)

    /// Elevated overlay shadow. Maps to Linear --shadow-xl:
    /// `rgba(8,9,10,0.6) 0 4px 32px`.
    public static let pop = NexusShadowProfile(
        color: Color(red: 8 / 255, green: 9 / 255, blue: 10 / 255).opacity(0.60),
        radius: 16,
        y: 4
    )

    /// Floating surface shadow (dialogs, sheets). Contained drop, no diffuse spread.
    public static let glass = NexusShadowProfile(color: .black.opacity(0.30), radius: 8, y: 4)

    /// Subtle contained shadow used near primary-action elements. Not a broad glow.
    public static let accentGlow = NexusShadowProfile(color: .black.opacity(0.25), radius: 4, y: 2)
}

extension View {
    public func nexusShadow(_ profile: NexusShadowProfile) -> some View {
        self.shadow(color: profile.color, radius: profile.radius, x: profile.x, y: profile.y)
    }
}
