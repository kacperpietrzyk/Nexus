#if os(macOS)
import SwiftUI

/// Left category rail for the two-pane Settings layout.
///
/// Displays all `SettingsCategory` cases as icon+label buttons with the
/// Inbox-row selected/hover/press idiom: `glassSelected` fill + hairline
/// stroke on the active row, `white.opacity(0.04)` wash on hover,
/// `NexusPressableButtonStyle` press scale.
public struct SettingsCategoryRail: View {
    @Binding public var selected: SettingsCategory

    public init(selected: Binding<SettingsCategory>) {
        _selected = selected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(SettingsCategory.allCases) { category in
                RailRow(
                    category: category,
                    isSelected: selected == category,
                    action: { selected = category }
                )
            }
        }
        .padding(DS.Space.m)
        .frame(width: 200, alignment: .leading)
    }
}

// MARK: - Rail row

private struct RailRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        isSelected
                            ? DS.ColorToken.textPrimary
                            : DS.ColorToken.textSecondary
                    )
                    .frame(width: 18, alignment: .center)

                Text(category.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(
                        isSelected
                            ? DS.ColorToken.textPrimary
                            : DS.ColorToken.textSecondary
                    )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(
                        isSelected
                            ? DS.ColorToken.glassSelected
                            : (hover ? Color.white.opacity(0.04) : Color.clear)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(isSelected ? DS.ColorToken.strokeHairline : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .onHover { value in
                withAnimation(DS.Motion.hover) { hover = value }
            }
        }
        .buttonStyle(NexusPressableButtonStyle())
    }
}

#Preview("SettingsCategoryRail") {
    HStack {
        SettingsCategoryRail(selected: .constant(.general))
        Spacer()
    }
    .frame(width: 240, height: 500)
    .background(DS.ColorToken.backgroundApp)
}
#endif
