import SwiftUI

/// Typography scale — Linear Midnight Command Center (spec §NexusType).
/// Size in points, tracking as em fraction (px ÷ size), lineHeight as multiplier of size.
/// Implementations target `Font.custom("Inter-*", ...)` and
/// `Font.custom("IBMPlexMono-*", ...)` — registered at app startup via
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

        // Tracking stored as em fraction: px ÷ size.
        // Applied as `size * tracking` → absolute pt offset in View.nexusType(_:).

        public static let display = Metrics(
            size: 48,
            lineHeight: 1.06,
            tracking: -0.22 / 48,
            weight: .semibold
        )
        public static let h1 = Metrics(
            size: 32,
            lineHeight: 1.12,
            tracking: -0.22 / 32,
            weight: .semibold
        )
        public static let h2 = Metrics(
            size: 24,
            lineHeight: 1.20,
            tracking: -0.22 / 24,
            weight: .semibold
        )
        public static let h3 = Metrics(
            size: 17,
            lineHeight: 1.30,
            tracking: -0.13 / 17,
            weight: .medium
        )
        public static let body = Metrics(
            size: 14,
            lineHeight: 1.45,
            tracking: -0.13 / 14,
            weight: .regular
        )
        public static let bodySmall = Metrics(
            size: 13,
            lineHeight: 1.55,
            tracking: -0.12 / 13,
            weight: .regular
        )
        public static let meta = Metrics(
            size: 12,
            lineHeight: 1.50,
            tracking: -0.11 / 12,
            weight: .regular
        )
        public static let caption = Metrics(
            size: 11,
            lineHeight: 1.40,
            tracking: -0.10 / 11,
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
    /// Compact monospace label — `IBMPlexMono-Medium` 10 pt.
    /// Used for kbd shortcuts, count badges, and UI chrome metadata where
    /// `mono` (12 pt Regular) is too large.
    public static let metaMono = Font.custom("IBMPlexMono-Medium", size: 10)

    static let monoFontName = "IBMPlexMono-Regular"

    static func fontName(for metrics: Metrics) -> String {
        switch metrics.weight {
        case .bold:
            return "Inter-Bold"
        case .semibold:
            return "Inter-SemiBold"
        case .medium:
            return "Inter-Medium"
        default:
            return "Inter-Regular"
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
