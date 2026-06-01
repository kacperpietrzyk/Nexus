import CoreGraphics
import Foundation

/// Linear "Midnight Command Center" radius scale.
/// Linear is tight: most components use 6 px; tags use 2 px; badges use 4 px.
public enum NexusRadius {
    // MARK: - Numeric scale
    public static let r1: CGFloat = 6
    public static let r2: CGFloat = 6
    public static let r3: CGFloat = 12
    public static let r4: CGFloat = 16
    public static let r5: CGFloat = 20

    // MARK: - Semantic aliases
    /// Full capsule / pill shape.
    public static let pill: CGFloat = 999
    /// Inline tag chip — 2 px per DESIGN.md `--radius-tags`.
    public static let tag: CGFloat = 2
    /// Small badge / count bubble — 4 px per DESIGN.md `--radius-badges`.
    public static let badge: CGFloat = 4
}
