import SwiftUI

// MARK: - NexusToggle

/// The canonical labeled switch row — the themed replacement for a native
/// `Toggle("label", isOn:)`, which on macOS renders as a system checkbox/switch
/// whose blue chrome clashes with the Liquid palette.
///
/// Layout: a leading label (with optional secondary caption) on the left, a
/// custom Liquid switch on the right, filling the row width. The switch track is
/// a flat `Background.control` capsule (off) that fills with the Liquid accent
/// (on); the knob is a porcelain circle. `NexusCheckbox` remains the bare,
/// label-less square for list/grid selection — this is the form-row variant.
///
/// Usage:
/// ```swift
/// NexusToggle("Pin as focus", isOn: $pinned)
/// NexusToggle("Preload model", caption: "Loads at launch", isOn: $preload)
/// ```
public struct NexusToggle: View {

    private let label: String
    private let caption: String?
    @Binding private var isOn: Bool
    private let isEnabled: Bool

    public init(
        _ label: String,
        caption: String? = nil,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) {
        self.label = label
        self.caption = caption
        self._isOn = isOn
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(NexusType.bodySmall)
                        .foregroundStyle(isEnabled ? NexusColor.Text.primary : NexusColor.Text.disabled)
                    if let caption {
                        Text(caption)
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }
                }
                Spacer(minLength: 8)
                NexusSwitchTrack(isOn: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - NexusSwitchTrack

/// The Liquid switch visual: a flat capsule track that fills with the accent
/// when on, and a porcelain knob that slides. Kept separate so the on/off
/// geometry lives in one place (and is unit-testable via `isOn`).
struct NexusSwitchTrack: View {
    let isOn: Bool

    static let width: CGFloat = 36
    static let height: CGFloat = 20

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? NexusColor.Accent.lime : NexusColor.Background.control)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? Color.clear : NexusColor.Line.strong, lineWidth: 1)
                )

            Circle()
                .fill(isOn ? NexusColor.Accent.limeInk : NexusColor.Text.secondary)
                .padding(2)
        }
        .frame(width: Self.width, height: Self.height)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

#if DEBUG
#Preview {
    struct Demo: View {
        @State private var pin = true
        @State private var allDay = false
        var body: some View {
            VStack(spacing: 12) {
                NexusToggle("Pin as focus", isOn: $pin)
                NexusToggle("All-day", isOn: $allDay)
                NexusToggle("Preload model", caption: "Loads at launch", isOn: $pin)
            }
            .padding(40)
            .frame(width: 320)
            .background(NexusColor.Background.base)
        }
    }
    return Demo()
}
#endif
