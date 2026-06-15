import SwiftUI

/// DS-canon press feedback for Liquid components, per `docs/03_COMPONENTS.md`
/// §Button motion.
///
/// Replicates the press scale of the shared legacy `NexusPressableButtonStyle`
/// (still used by iOS) — `0.97` on press — but animates with `DS.Motion.press`
/// (easeOut 80 ms) instead of `NexusMotion.press`. Liquid buttons adopt this so
/// they sit entirely on the DS motion namespace and don't straddle the two
/// motion namespaces the design system carries (`DS.Motion` canonical +
/// `NexusMotion` residue).
public struct LiquidPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}
