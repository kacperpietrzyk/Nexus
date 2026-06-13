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
        .todayGlassSurface(isHovering: hovering)
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

private struct TodayGlassSurface: ViewModifier {
    let isHovering: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: todayCardCornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(Color.white.opacity(isHovering ? 0.020 : 0.010))
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape
                            .fill(DS.ColorToken.glassCard.opacity(isHovering ? 0.18 : 0.090))
                    }
                    .overlay {
                        shape
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(isHovering ? 0.12 : 0.088), location: 0),
                                        .init(color: Color.white.opacity(0.018), location: 0.20),
                                        .init(color: .clear, location: 0.58),
                                        .init(color: Color.black.opacity(0.030), location: 1),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                    }
                    .overlay {
                        shape
                            .fill(
                                RadialGradient(
                                    colors: [
                                        DS.ColorToken.accentBlue.opacity(isHovering ? 0.026 : 0.016),
                                        .clear,
                                    ],
                                    center: UnitPoint(x: 0.08, y: 0.02),
                                    startRadius: 12,
                                    endRadius: 520
                                )
                            )
                            .blendMode(.screen)
                    }
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovering ? 0.30 : 0.22),
                                Color.white.opacity(0.046),
                                Color.black.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: todayCardCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isHovering ? 0.18 : 0.11), lineWidth: 0.5)
                    .blur(radius: 0.45)
                    .padding(0.5)
                    .blendMode(.screen)
            }
            .shadow(color: Color.black.opacity(0.070), radius: 8, x: 0, y: 4)
    }
}

private extension View {
    func todayGlassSurface(isHovering: Bool) -> some View {
        modifier(TodayGlassSurface(isHovering: isHovering))
    }
}
