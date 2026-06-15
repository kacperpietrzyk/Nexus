import SwiftUI

/// A single tab in a ``LiquidTabBar``. Mirrors `NexusTabBarItem` so a future
/// swap from the legacy bar is mechanical.
public struct LiquidTabBarItem<ID: Hashable>: Identifiable, @unchecked Sendable {
    public let id: ID
    public let label: String
    public let systemImage: String?
    public let count: Int?

    public init(id: ID, label: String, systemImage: String? = nil, count: Int? = nil) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.count = count
    }
}

/// Glass tab bar per `docs/03_COMPONENTS.md` §TabBar — the Liquid counterpart
/// to the legacy `NexusTabBar`, sharing its `items:` / `active:` API.
///
/// A horizontal row of label buttons over a `strokeHairline` top rule. The
/// active item carries `accentPrimary` ink plus a thin accent underline
/// (animated via `matchedGeometryEffect` with `DS.Motion.selection`); idle
/// items are `textSecondary`. An optional `count` renders as a small pill.
public struct LiquidTabBar<ID: Hashable>: View {

    public let items: [LiquidTabBarItem<ID>]
    @Binding public var active: ID

    @Namespace private var underline
    #if os(macOS)
    @State private var hoveredID: ID?
    #endif

    public init(items: [LiquidTabBarItem<ID>], active: Binding<ID>) {
        self.items = items
        self._active = active
    }

    /// Whether the given id is the active tab.
    internal func isActive(_ id: ID) -> Bool { Self.isActive(id, selected: active) }

    /// Pure active-tab check. Extracted as a static helper so it can be
    /// unit-tested without reading the `@Binding active` through a `View`
    /// instance (which traps outside the SwiftUI update loop).
    internal static func isActive(_ id: ID, selected: ID) -> Bool { id == selected }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                tabButton(for: item)
            }
        }
        .padding(.horizontal, DS.Space.s)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(height: 1)
        }
    }

    private func tabButton(for item: LiquidTabBarItem<ID>) -> some View {
        Button {
            withAnimation(DS.Motion.selection) { active = item.id }
        } label: {
            tabLabel(for: item)
                .padding(.horizontal, DS.Space.m)
                .frame(height: 32)
                .foregroundStyle(ink(for: item.id))
                .overlay(alignment: .bottom) {
                    if isActive(item.id) {
                        Capsule(style: .continuous)
                            .fill(DS.ColorToken.accentPrimary)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "liquidTabUnderline", in: underline)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isActive(item.id) ? [.isSelected, .isButton] : [.isButton])
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hoveredID = value ? item.id : nil }
        }
        #endif
    }

    private func ink(for id: ID) -> Color {
        if isActive(id) { return DS.ColorToken.accentPrimary }
        #if os(macOS)
        if hoveredID == id { return DS.ColorToken.textPrimary }
        #endif
        return DS.ColorToken.textSecondary
    }

    private func tabLabel(for item: LiquidTabBarItem<ID>) -> some View {
        HStack(spacing: DS.Space.xs) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(item.label)
                .font(DS.FontToken.bodyStrong)
            if let count = item.count {
                LiquidPill(
                    "\(count)",
                    color: isActive(item.id) ? DS.ColorToken.accentPrimary : DS.ColorToken.textTertiary
                )
            }
        }
    }
}
