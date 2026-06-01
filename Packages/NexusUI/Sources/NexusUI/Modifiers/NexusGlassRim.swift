import SwiftUI

/// Edge rim over a surface.
///
/// Retargeted for Linear "Midnight Command Center": a single flat 1px
/// `Line.regular` stroke around the shape — no top-edge refraction gradient.
/// The legacy refraction constants are retained as frozen-API guards (the body
/// no longer reads them).
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

    public func body(content: Content) -> some View {
        content.overlay {
            shape
                .stroke(NexusColor.Line.regular, lineWidth: 1)
                .allowsHitTesting(false)
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
