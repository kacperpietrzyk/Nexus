import NexusUI
import SwiftUI

private let todayCardCornerRadius: CGFloat = 12

/// Today-specific rim card tuned against `references/01_today_dashboard.png`.
///
/// The shell owns the actual material sample. These cards only add rim light,
/// local glare, and slight absorption so the screen does not become a stack of
/// nested blur panels.
struct TodayGlassCard<Content: View, Trailing: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    @State private var hovering = false

    init(
        _ title: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if let title {
                HStack {
                    Text(title)
                        .font(DS.FontToken.section)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s)
                    trailing()
                }
                .frame(minHeight: 24, alignment: .center)
            }

            content()
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidLightCard(cornerRadius: todayCardCornerRadius, isHovering: hovering)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}

extension TodayGlassCard where Trailing == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, content: content, trailing: { EmptyView() })
    }
}
