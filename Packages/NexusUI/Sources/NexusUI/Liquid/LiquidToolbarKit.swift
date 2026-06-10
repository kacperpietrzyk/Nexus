import SwiftUI

/// Segment height — toolbar controls sit inside the 32 pt search-field line
/// (`docs/03_COMPONENTS.md` §Toolbar); segments are slightly shorter so the
/// soft track wraps them with breathing room.
private let segmentHeight: CGFloat = 24

/// Toolbar search affordance per `docs/03_COMPONENTS.md` §Toolbar/§SearchField.
///
/// 32 pt tall, soft glass fill, magnifier + placeholder, trailing `⌘ K` hint
/// pill. This is a button, not a live `TextField` — activating it should open
/// the command palette / search overlay.
///
/// Spec radius is 9 pt; `DS.Radius.s` (8 pt) is the closest token and is used
/// instead of a one-off constant.
public struct LiquidSearchField: View {

    public let placeholder: String
    public let shortcutHint: String?
    public let action: () -> Void

    public init(_ placeholder: String = "Search…", shortcutHint: String? = "⌘ K", action: @escaping () -> Void = {}) {
        self.placeholder = placeholder
        self.shortcutHint = shortcutHint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "magnifyingglass")
                    // 12 pt magnifier sits optically level with the 13 pt body placeholder
                    // inside the 32 pt field (03_COMPONENTS.md §SearchField); no icon-size token.
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.ColorToken.textTertiary)

                Text(placeholder)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: DS.Space.s)

                if let shortcutHint {
                    Text(shortcutHint)
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textMuted)
                        .padding(.horizontal, DS.Space.xs)
                        .frame(height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                                .fill(DS.ColorToken.glassSelected)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
                                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, DS.Space.s)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(DS.ColorToken.glassSoft)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(placeholder)
    }
}

/// One option in a ``LiquidSegmentedControl``.
public struct LiquidSegmentOption<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String

    public var id: Value { value }

    public init(_ value: Value, label: String) {
        self.value = value
        self.label = label
    }
}

/// Glass segmented control (Day / Week / Month, board scopes, …).
///
/// Soft glass track; the active segment is a `glassSelected` pill that moves
/// with `DS.Motion.selection`.
public struct LiquidSegmentedControl<Value: Hashable>: View {

    public let options: [LiquidSegmentOption<Value>]
    @Binding public var selection: Value

    public init(options: [LiquidSegmentOption<Value>], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isActive = option.value == selection
                Button {
                    withAnimation(DS.Motion.selection) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(isActive ? DS.FontToken.bodyStrong : DS.FontToken.body)
                        .foregroundStyle(isActive ? DS.ColorToken.textPrimary : DS.ColorToken.textTertiary)
                        .padding(.horizontal, DS.Space.m)
                        .frame(height: segmentHeight)
                        .background {
                            if isActive {
                                Capsule(style: .continuous)
                                    .fill(DS.ColorToken.glassSelected)
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(DS.ColorToken.glassSoft)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
    }
}

#if os(macOS)
#Preview("Toolbar kit") {
    struct Demo: View {
        @State private var scope = "week"
        var body: some View {
            HStack(spacing: DS.Space.m) {
                LiquidSearchField()
                    .frame(width: 280)
                LiquidSegmentedControl(
                    options: [
                        .init("day", label: "Day"),
                        .init("week", label: "Week"),
                        .init("month", label: "Month"),
                    ],
                    selection: $scope
                )
            }
            .padding(40)
            .background(DS.ColorToken.backgroundApp)
        }
    }
    return Demo()
}
#endif
