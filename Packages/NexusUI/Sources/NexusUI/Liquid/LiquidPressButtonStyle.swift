import SwiftUI

/// DS-canon press feedback for Liquid components, per `docs/03_COMPONENTS.md`
/// §Button motion.
///
/// Replicates the press scale of the shared legacy `NexusPressableButtonStyle`
/// (still used by iOS) — `0.97` on press — and animates with `DS.Motion.press`
/// (easeOut 80 ms). Liquid buttons sit entirely on the canonical `DS.Motion`
/// namespace.
public struct LiquidPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}
