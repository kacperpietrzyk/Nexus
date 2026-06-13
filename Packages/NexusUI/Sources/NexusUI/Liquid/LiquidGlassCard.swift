import SwiftUI

/// Titled liquid glass card — the workhorse container of the design system.
///
/// Anatomy per `docs/03_COMPONENTS.md` §GlassCard: optional header row
/// (section-font title + trailing accessory slot), then the body content.
/// On macOS the card brightens on hover.
///
/// The `trailing` slot is a header-row accessory: it renders only when
/// `title != nil` (intentional — without a title there is no header row to
/// host it; put standalone chrome in `content` instead).
public struct LiquidGlassCard<Content: View, Trailing: View>: View {

    public let title: String?
    @ViewBuilder public var content: () -> Content
    @ViewBuilder public var trailing: () -> Trailing

    @State private var hovering = false

    public init(
        _ title: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.content = content
        self.trailing = trailing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if let title {
                HStack {
                    Text(title)
                        .font(DS.FontToken.section)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    trailing()
                }
                .frame(height: 24)
            }
            content()
        }
        .padding(DS.Space.l)
        .liquidGlass(.card, radius: DS.Radius.l, isHovering: hovering)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}

extension LiquidGlassCard where Trailing == EmptyView {
    /// Titled card without a trailing header accessory.
    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, content: content, trailing: { EmptyView() })
    }
}

#if os(macOS)
#Preview("LiquidGlassCard") {
    LiquidGlassCard("Today") {
        Text("Card body")
            .font(DS.FontToken.body)
            .foregroundStyle(DS.ColorToken.textSecondary)
    }
    .padding(40)
    .background(DS.ColorToken.backgroundApp)
}
#endif
