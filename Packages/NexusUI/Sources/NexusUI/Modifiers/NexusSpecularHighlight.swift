import SwiftUI

/// Cursor-tracked specular highlight on glass surfaces. macOS only —
/// no-ops on iOS / watchOS / visionOS where there is no continuous-hover API.
///
/// Canvas: `glass-tokens.css` `.glass-spec` :78-83 — radial 220×160 px, warm
/// cream tint, `mix-blend-mode: screen`. SwiftUI's closest equivalent is
/// `.blendMode(.screen)`. Hidden under Reduce Transparency.
public struct NexusSpecularHighlight: ViewModifier {

    public static let tintColor: Color = NexusColor.Glass.surface3
    public static let defaultRadius: CGFloat = 220

    public init() {}

    #if os(macOS)
    @State private var location: CGPoint = .zero
    @State private var isHovered = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        content.overlay {
            if !reduceTransparency, isHovered {
                GeometryReader { geo in
                    RadialGradient(
                        colors: [NexusSpecularHighlight.tintColor, .clear],
                        center: UnitPoint(
                            x: location.x / max(geo.size.width, 1),
                            y: location.y / max(geo.size.height, 1)
                        ),
                        startRadius: 0,
                        endRadius: NexusSpecularHighlight.defaultRadius
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                isHovered = true
                location = point
            case .ended:
                isHovered = false
            }
        }
    }
    #else
    public func body(content: Content) -> some View {
        content
    }
    #endif
}

extension View {
    /// Mac-only cursor-tracked specular highlight. No-ops on every other platform.
    public func nexusSpecularHighlight() -> some View {
        modifier(NexusSpecularHighlight())
    }
}
