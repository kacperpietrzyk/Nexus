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

/// Flat surface modifier — the Linear "Midnight Command Center" substrate
/// behind primary surfaces. Retargeted from translucent glass to a flat
/// layered fill: an elevated `Background.raised` surface, a 1px neutral
/// `Line.regular` rim, and a subtle contained `NexusShadow.s1` drop. No
/// `.ultraThinMaterial` blur, no specular highlight, no glow — Linear is flat.
///
/// The `NexusGlassVariant` axis and its per-variant tint / border / shadow
/// constants are retained (and still asserted by the frozen-API tests) but the
/// body no longer reads them: every variant renders the same flat elevated
/// surface so chrome reads uniformly across all call sites.
///
/// Generic over the clip `Shape` (NOT `InsettableShape`) so cards
/// (`RoundedRectangle`) and pills (`Capsule`) share the same modifier and the
/// public API stays frozen. The rim uses `shape.stroke(_:lineWidth:)` rather
/// than `strokeBorder` (which requires `InsettableShape`); the 1pt visual delta
/// from centred-vs-inset stroking is negligible and preserving `Shape` keeps
/// the frozen public surface intact. Use the shorthand `.nexusGlass(.regular)`
/// for rounded-rectangle cards or `.nexusGlass(.regular, in: Capsule())` for
/// capsule-shaped surfaces.
public struct NexusGlassMaterial<S: Shape>: ViewModifier {

    public let variant: NexusGlassVariant
    public let shape: S

    public init(variant: NexusGlassVariant = .regular, shape: S) {
        self.variant = variant
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        // Linear "Midnight Command Center" is FLAT: an elevated `Background.*`
        // surface, a 1px neutral `Line` rim, and a subtle contained shadow —
        // no `.ultraThinMaterial` blur, no specular gradient, no glow. The
        // 3-variant axis collapses to a single elevated fill so chrome reads
        // uniformly flat across all call sites; the variant-specific tint /
        // shadow constants below are retained only as frozen-API guards.
        content
            .background(NexusColor.Background.raised, in: shape)
            // Clip `content` (not just the fill) to the shape — preserves the
            // pre-migration contract for all arbitrary-`Shape` call sites so
            // edge-to-edge content doesn't bleed past the rounded surface.
            // Shadow is applied last (outside the clip).
            .clipShape(shape)
            .overlay(shape.stroke(NexusColor.Line.regular, lineWidth: 1))
            .nexusShadow(NexusShadow.s1)
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
