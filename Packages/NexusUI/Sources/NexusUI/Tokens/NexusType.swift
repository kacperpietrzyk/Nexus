import SwiftUI

/// Typography scale — Amber 8-step (spec §13.3).
/// Size in points, tracking as em fraction, lineHeight as multiplier of size.
/// Implementations target `Font.custom("Geist-*", ...)` and
/// `Font.custom("GeistMono-*", ...)` — registered at app startup via
/// `NexusFontRegistration.registerAll()`. If registration fails, SwiftUI
/// falls back to the system font automatically.
public enum NexusType {

    public struct Metrics: Sendable, Equatable {
        public let size: Double
        /// Multiplier of `size`. Stored on `Metrics` but **not** applied by `View.nexusType(_:)` —
        /// primitives that need line height must call `.lineSpacing((lineHeight - 1) * size)` explicitly.
        public let lineHeight: Double
        public let tracking: Double
        public let weight: Font.Weight
        public let uppercase: Bool

        public init(
            size: Double,
            lineHeight: Double,
            tracking: Double,
            weight: Font.Weight,
            uppercase: Bool = false
        ) {
            self.size = size
            self.lineHeight = lineHeight
            self.tracking = tracking
            self.weight = weight
            self.uppercase = uppercase
        }

        public static let display = Metrics(
            size: 48,
            lineHeight: 1.06,
            tracking: -0.04,
            weight: .semibold
        )
        public static let h1 = Metrics(
            size: 32,
            lineHeight: 1.12,
            tracking: -0.03,
            weight: .semibold
        )
        public static let h2 = Metrics(
            size: 22,
            lineHeight: 1.20,
            tracking: -0.02,
            weight: .semibold
        )
        public static let h3 = Metrics(
            size: 18,
            lineHeight: 1.30,
            tracking: -0.02,
            weight: .medium
        )
        public static let body = Metrics(
            size: 13.5,
            lineHeight: 1.45,
            tracking: -0.005,
            weight: .regular
        )
        public static let bodySmall = Metrics(
            size: 13,
            lineHeight: 1.55,
            tracking: -0.005,
            weight: .regular
        )
        public static let meta = Metrics(
            size: 12,
            lineHeight: 1.50,
            tracking: 0,
            weight: .regular
        )
        public static let caption = Metrics(
            size: 11,
            lineHeight: 1.40,
            tracking: 0,
            weight: .regular
        )
        public static let eyebrow = Metrics(
            size: 10,
            lineHeight: 1.0,
            tracking: 0.18,
            weight: .semibold,
            uppercase: true
        )
    }

    // MARK: - Font factories
    // Use these when only `.font(NexusType.h1)` is needed (no tracking, textCase,
    // or lineHeight). Use `NexusType.Metrics.*` with `View.nexusType(_:)` when you
    // also need tracking + textCase. lineHeight remains caller's responsibility.

    public static let display = font(for: Metrics.display)
    public static let h1 = font(for: Metrics.h1)
    public static let h2 = font(for: Metrics.h2)
    public static let h3 = font(for: Metrics.h3)
    public static let body = font(for: Metrics.body)
    public static let bodySmall = font(for: Metrics.bodySmall)
    public static let meta = font(for: Metrics.meta)
    public static let caption = font(for: Metrics.caption)
    public static let eyebrow = font(for: Metrics.eyebrow)
    public static let mono = Font.custom(monoFontName, size: 12)
    /// Compact monospace label — `GeistMono-Medium` 10 pt.
    /// Used for kbd shortcuts, count badges, and UI chrome metadata where
    /// `mono` (12 pt Regular) is too large (§8 stopgap sites).
    public static let metaMono = Font.custom("GeistMono-Medium", size: 10)

    static let monoFontName = "GeistMono-Regular"

    static func fontName(for metrics: Metrics) -> String {
        switch metrics.weight {
        case .bold:
            return "Geist-Bold"
        case .semibold:
            return "Geist-SemiBold"
        case .medium:
            return "Geist-Medium"
        default:
            return "Geist-Regular"
        }
    }

    private static func font(for metrics: Metrics) -> Font {
        Font.custom(fontName(for: metrics), size: metrics.size)
    }
}

// MARK: - Convenience modifier

extension View {
    /// Apply a NexusType metrics block — sets font, tracking, and (optionally) uppercases via `textCase`.
    /// Line height is implicit via SwiftUI default for system font; custom line spacing is added
    /// only where the design canvas calls for non-default value (handled in primitives).
    public func nexusType(_ metrics: NexusType.Metrics) -> some View {
        let base =
            self
            .font(Font.custom(NexusType.fontName(for: metrics), size: metrics.size))
            .tracking(metrics.size * metrics.tracking)
        // Group + if/else (not ternary on .textCase): leave inherited textCase
        // untouched when metrics.uppercase == false.
        return Group {
            if metrics.uppercase {
                base.textCase(.uppercase)
            } else {
                base
            }
        }
    }
}
