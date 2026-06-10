import SwiftUI

/// Nav row corner radius — `docs/03_COMPONENTS.md` §Sidebar: "nav row radius: 10 pt".
/// No 10 pt entry in `DS.Radius`, so the spec value lives here.
private let navRowCornerRadius: CGFloat = 10
/// Hover wash — `docs/03_COMPONENTS.md` §LiquidGlassPanel states: "hover: fill jaśniejszy o 6–8%".
private let navRowHoverFill = Color.white.opacity(0.07)

/// Sidebar navigation row per `docs/03_COMPONENTS.md` §Sidebar.
///
/// 34 pt tall: 16 pt SF Symbol slot, title, optional trailing badge count
/// (min 20×20 pt pill). Selection renders the `glassSelected` fill with a
/// `strokeDefault` border and an optional 2 pt leading accent line; hover
/// adds a subtle white wash (macOS only).
public struct LiquidSidebarNavRow: View {

    public let title: String
    public let systemImage: String
    public let badge: Int?
    public let isSelected: Bool
    public let showsSelectionAccent: Bool
    public let action: () -> Void

    @State private var hovering = false

    public init(
        _ title: String,
        systemImage: String,
        badge: Int? = nil,
        isSelected: Bool = false,
        showsSelectionAccent: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
        self.isSelected = isSelected
        self.showsSelectionAccent = showsSelectionAccent
        self.action = action
    }

    private var fill: Color {
        if isSelected { return DS.ColorToken.glassSelected }
        return hovering ? navRowHoverFill : .clear
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: systemImage)
                    // 13 pt symbol inside the 16 pt icon slot (03_COMPONENTS.md §Sidebar:
                    // "icon size: 16 pt" refers to the slot; symbol point size is optical).
                    // Medium weight is deliberate — heavier than DS.FontToken.body's regular
                    // so glyphs hold up against the 13 pt title at sidebar density.
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(isSelected ? DS.FontToken.bodyStrong : DS.FontToken.body)
                    .foregroundStyle(isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let badge {
                    Text("\(badge)")
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .padding(.horizontal, DS.Space.xs)
                        .frame(minWidth: 20, minHeight: 20)
                        .background {
                            Capsule(style: .continuous)
                                .fill(DS.ColorToken.glassSelected)
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, DS.Space.s)
            .frame(height: DS.Size.navItemHeight)
            .background {
                RoundedRectangle(cornerRadius: navRowCornerRadius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: navRowCornerRadius, style: .continuous)
                        .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected && showsSelectionAccent {
                    Capsule(style: .continuous)
                        .fill(DS.ColorToken.accentPrimary)
                        .frame(width: 2, height: DS.Size.navItemHeight - 2 * DS.Space.s)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}

/// Uppercase sidebar section header (Workspaces, Views, …).
public struct LiquidSidebarSectionHeader: View {

    public let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textMuted)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

#if os(macOS)
#Preview("Sidebar rows") {
    VStack(alignment: .leading, spacing: DS.Space.xxs) {
        LiquidSidebarSectionHeader("Views")
        LiquidSidebarNavRow("Today", systemImage: "sun.max", isSelected: true)
        LiquidSidebarNavRow("Inbox", systemImage: "tray", badge: 4)
    }
    .padding(DS.Space.m)
    .frame(width: 224)
    .background(DS.ColorToken.backgroundApp)
}
#endif
