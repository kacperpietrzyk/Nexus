import SwiftUI

// MARK: - NexusStepper

/// The canonical labeled numeric stepper row — the themed replacement for a
/// native `Stepper`, whose system +/- chrome clashes with the Liquid palette.
///
/// Layout: a leading label on the left, then a control-tile group on the right
/// holding the current value between flat `−`/`+` buttons (same tile recipe as
/// `NexusTextField`/`NexusDateField`). Clamps to `range` and disables the bound
/// button at each end.
///
/// Usage:
/// ```swift
/// NexusStepper("Buffer", value: $minutes, in: 0...60, step: 5, unit: "min")
/// NexusStepper("Daily goal", value: $goal, in: 0...99)
/// ```
public struct NexusStepper: View {

    private let label: String
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let unit: String?

    public init(
        _ label: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        unit: String? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
            Spacer(minLength: 8)
            controlGroup
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
    }

    private var controlGroup: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", action: decrement, enabled: value > range.lowerBound)

            Text(valueText)
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
                .monospacedDigit()
                .frame(minWidth: unit == nil ? 30 : 56)
                .padding(.vertical, 6)

            stepButton(systemImage: "plus", action: increment, enabled: value < range.upperBound)
        }
        .background(
            NexusColor.Background.control,
            in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        )
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void, enabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? NexusColor.Text.secondary : NexusColor.Text.disabled)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHidden(true)
    }

    private var valueText: String {
        Self.formatted(value: value, unit: unit)
    }

    private func increment() {
        value = Self.incremented(value, by: step, in: range)
    }

    private func decrement() {
        value = Self.decremented(value, by: step, in: range)
    }

    // MARK: - Pure logic (testable)

    /// One step up, clamped to the upper bound.
    static func incremented(_ value: Int, by step: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, value + step)
    }

    /// One step down, clamped to the lower bound.
    static func decremented(_ value: Int, by step: Int, in range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, value - step)
    }

    /// Trailing-unit value label (e.g. "15 min"); bare number when no unit.
    static func formatted(value: Int, unit: String?) -> String {
        unit.map { "\(value) \($0)" } ?? "\(value)"
    }
}

#if DEBUG
#Preview {
    struct Demo: View {
        @State private var buffer = 15
        @State private var goal = 3
        var body: some View {
            VStack(spacing: 12) {
                NexusStepper("Buffer", value: $buffer, in: 0...60, step: 5, unit: "min")
                NexusStepper("Daily goal", value: $goal, in: 0...99)
            }
            .padding(40)
            .frame(width: 320)
            .background(NexusColor.Background.base)
        }
    }
    return Demo()
}
#endif
