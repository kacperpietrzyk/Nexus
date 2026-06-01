#if !os(watchOS)
import SwiftUI

public struct NexusTabBarItem<ID: Hashable>: Identifiable, @unchecked Sendable {
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

public struct NexusTabBar<ID: Hashable>: View {
    internal static var itemHeight: CGFloat { 26 }
    internal static var horizontalPadding: CGFloat { 12 }

    public let items: [NexusTabBarItem<ID>]
    @Binding public var active: ID

    public init(items: [NexusTabBarItem<ID>], active: Binding<ID>) {
        self.items = items
        self._active = active
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    active = item.id
                } label: {
                    tabLabel(for: item)
                        .padding(.horizontal, Self.horizontalPadding)
                        .frame(height: Self.itemHeight)
                        .foregroundStyle(item.id == active ? NexusColor.Accent.lime : NexusColor.Text.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
        .padding(3)
        .background(NexusColor.Background.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(height: 1)
        }
    }

    private func tabLabel(for item: NexusTabBarItem<ID>) -> some View {
        HStack(spacing: 5) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
            }

            Text(item.label)
                .font(NexusType.body.weight(.semibold))

            if let count = item.count {
                Text("\(count)")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
        }
    }
}
#endif
