import SwiftUI

/// Variant axis for `NexusGlassMaterial`. Hoisted to top-level so callers can
/// reference it without supplying the modifier's `Shape` generic argument.
public enum NexusGlassVariant: CaseIterable, Sendable {
    case subtle
    case regular
    case elevated

    /// Per-variant glass tint colour.
    ///
    /// - Note: Superseded by the native substrate
    ///   (`NexusGlassMaterial.substrate(_:)`) as of the MP-0 LabKit
    ///   reconciliation — the modifier body no longer reads this. Kept because
    ///   it is asserted symbol-vs-symbol by the frozen-API tests
    ///   (`variantTintMatchesV4GlassTokens`); slated for MP-1 cleanup.
    var tint: Color {
        switch self {
        case .subtle: return NexusColor.Glass.surface1
        case .regular: return NexusColor.Glass.surface2
        case .elevated: return NexusColor.Glass.surface3
        }
    }

    /// Per-variant hairline border colour.
    ///
    /// - Note: Superseded by the built-in LabKit rim gradient
    ///   (`NexusGlassMaterial.rimGradientColors`) as of the MP-0 LabKit
    ///   reconciliation — the modifier body no longer reads this. Kept because
    ///   it is asserted symbol-vs-symbol by the frozen-API tests
    ///   (`variantBorderColor`); slated for MP-1 cleanup.
    var borderColor: Color {
        switch self {
        case .subtle: return NexusColor.Line.hairline
        case .regular: return NexusColor.Line.regular
        case .elevated: return NexusColor.Line.strong
        }
    }

    /// Solid colour used when `accessibilityReduceTransparency == true`.
    var opaqueFallback: Color {
        switch self {
        case .subtle: return NexusColor.Background.panel
        case .regular: return NexusColor.Background.raised
        case .elevated: return NexusColor.Background.control
        }
    }

    /// Collapses the 3-variant axis onto LabGlass's binary `elevated` flag.
    /// `.elevated` → `true` (deep shadow); `.subtle`/`.regular` → `false`
    /// (shallow shadow). Only the two LabKit-locked shadow value-sets exist —
    /// there is deliberately no 3-way shadow scale.
    var isElevatedSurface: Bool { self == .elevated }
}

/// Glass material modifier — the v4 substrate behind primary surfaces,
/// reconciled to the LabKit `LabGlass` look in the MP-0 migration.
///
/// On macOS 26+ the substrate is native `.glassEffect(.regular,)`; below 26
/// (or under `accessibilityReduceTransparency`) it collapses to an opaque-ish
/// fill. In **all** branches a 1pt LabKit rim gradient and the LabKit
/// elevation shadow are applied — chrome always carries the rim + shadow, even
/// under reduced transparency (LabGlass discipline + spec §5 accessibility
/// invariant, which requires the Reduce-Transparency branch to remain).
///
/// The 3-variant `NexusGlassVariant` axis maps onto LabGlass's binary
/// `elevated`: `.elevated → elevated:true`, `.subtle`/`.regular →
/// elevated:false` (see `NexusGlassVariant.isElevatedSurface`).
///
/// Generic over the clip `Shape` (NOT `InsettableShape`) so cards
/// (`RoundedRectangle`) and pills (`Capsule`) share the same modifier and the
/// public API stays frozen. Because the constraint is `Shape`, the rim uses
/// `shape.stroke(_:lineWidth:)` rather than LabGlass's
/// `strokeBorder` (`strokeBorder` requires `InsettableShape`); the 1pt visual
/// delta from centred-vs-inset stroking is negligible and preserving `Shape`
/// keeps the frozen public surface intact. Use the shorthand
/// `.nexusGlass(.regular)` for rounded-rectangle cards or
/// `.nexusGlass(.regular, in: Capsule())` for capsule-shaped surfaces.
public struct NexusGlassMaterial<S: Shape>: ViewModifier {

    public let variant: NexusGlassVariant
    public let shape: S

    public init(variant: NexusGlassVariant = .regular, shape: S) {
        self.variant = variant
        self.shape = shape
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        let elevated = variant.isElevatedSurface

        return substrate(content)
            // Preserve the pre-migration contract: `content` (not just the
            // substrate) is clipped to the arbitrary `Shape`. LabGlass clips
            // only the substrate via `in: shape`; production keeps the
            // explicit clip so existing arbitrary-`Shape` clipping behaviour
            // for all 9 call sites is unchanged. Shadow is applied last
            // (after the clip), as in LabGlass.
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: Self.rimGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: Self.rimLineWidth
                )
            )
            .shadow(
                color: .black.opacity(Self.shadowOpacity(elevated: elevated)),
                radius: Self.shadowRadius(elevated: elevated),
                y: Self.shadowY(elevated: elevated)
            )
    }

    @ViewBuilder
    private func substrate(_ content: Content) -> some View {
        if reduceTransparency {
            // spec §5 accessibility invariant: collapse to an opaque v4
            // surface. LabGlass has no such branch; production must keep it.
            content.background(variant.opaqueFallback, in: shape)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(NexusColor.Glass.surface1, in: shape)
        }
    }

    // MARK: - LabKit-exact look constants (single source of truth)
    //
    // The body builds the rim + shadow from these symbols, and the behaviour
    // tests assert these same symbols (mirrors the `NexusGlassRimSpec`
    // precedent). The values are LabKit-exact and frozen — see `LabGlass` in
    // `Lab/LabKit.swift`. Computed/`static let` because generic types cannot
    // declare static stored instance-generic properties.

    /// LabGlass rim: a top→bottom white gradient, 16% → 7% alpha.
    internal static var rimGradientColors: [Color] {
        [Color.white.opacity(0.16), Color.white.opacity(0.07)]
    }

    /// LabGlass rim stroke width.
    internal static var rimLineWidth: CGFloat { 1 }

    /// LabGlass shadow alpha — deep when elevated, shallow otherwise.
    internal static func shadowOpacity(elevated: Bool) -> Double {
        elevated ? 0.55 : 0.35
    }

    /// LabGlass shadow blur radius.
    internal static func shadowRadius(elevated: Bool) -> CGFloat {
        elevated ? 24 : 12
    }

    /// LabGlass shadow vertical offset.
    internal static func shadowY(elevated: Bool) -> CGFloat {
        elevated ? 12 : 5
    }

    /// Specular rim alpha at the top of the legacy glass gradient. Mirrors the
    /// canvas `--spec-top` token at 7% white.
    ///
    /// - Note: The MP-0 LabKit body no longer composes the old specular
    ///   gradient, so this is body-unused. Its value (white @ 7%) equals the
    ///   bottom stop of `rimGradientColors`. Kept because
    ///   `specularTopAlphaMatchesCanvasSpecToken` asserts it as a frozen-API
    ///   guard (not a snapshot of the look); slated for MP-1 cleanup.
    ///   Computed (not stored) because generic types cannot declare static
    ///   stored properties.
    internal static var specularTopAlpha: Color { Color.white.opacity(0.07) }
}

extension NexusGlassMaterial where S == RoundedRectangle {
    /// Build a rounded-rectangle glass surface from a corner radius.
    public init(
        variant: NexusGlassVariant = .regular,
        cornerRadius: CGFloat = NexusRadius.r3
    ) {
        self.init(
            variant: variant,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    /// Glass material — replaces solid surfaces in v4. Honours
    /// `accessibilityReduceTransparency` automatically. Rounded-rectangle
    /// convenience overload.
    public func nexusGlass(
        _ variant: NexusGlassVariant = .regular,
        cornerRadius: CGFloat = NexusRadius.r3
    ) -> some View {
        modifier(NexusGlassMaterial<RoundedRectangle>(variant: variant, cornerRadius: cornerRadius))
    }

    /// Glass material clipped to an arbitrary `Shape` — use for capsule pills
    /// and other non-rectangular surfaces.
    public func nexusGlass<S: Shape>(
        _ variant: NexusGlassVariant = .regular,
        in shape: S
    ) -> some View {
        modifier(NexusGlassMaterial(variant: variant, shape: shape))
    }
}
