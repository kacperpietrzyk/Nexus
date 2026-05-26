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
                        .foregroundStyle(item.id == active ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                        .background {
                            if item.id == active {
                                activeBackground
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
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

    private var activeBackground: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
#endif
