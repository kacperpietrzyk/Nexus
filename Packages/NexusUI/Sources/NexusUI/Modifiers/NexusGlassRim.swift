import SwiftUI

/// Top-edge refraction highlight over a glass surface.
///
/// v4 contract: white 7% -> 0% over 0% -> 40% of the surface height.
public enum NexusGlassRimSpec {
    public static let topOpacity: Double = 0.07
    public static let fadeEndLocation: CGFloat = 0.4
    public static let refractionColor: Color = Color.white.opacity(topOpacity)
}

public struct NexusGlassRim<S: Shape>: ViewModifier {

    public let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        content.overlay {
            if !reduceTransparency {
                LinearGradient(
                    stops: [
                        .init(color: NexusGlassRimSpec.refractionColor, location: 0),
                        .init(color: .white.opacity(0), location: NexusGlassRimSpec.fadeEndLocation),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Top-edge refraction highlight — pairs with `nexusGlass(...)`.
    public func nexusGlassRim<S: Shape>(in shape: S) -> some View {
        modifier(NexusGlassRim(shape: shape))
    }

    /// Convenience: rounded-rectangle rim at a given radius.
    public func nexusGlassRim(cornerRadius: CGFloat = NexusRadius.r3) -> some View {
        nexusGlassRim(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
