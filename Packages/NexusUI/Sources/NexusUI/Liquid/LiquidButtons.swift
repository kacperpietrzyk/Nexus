import SwiftUI

/// Hover fill for icon buttons — `docs/03_COMPONENTS.md` §IconButton: "hover fill #FFFFFF10".
private let iconButtonHoverFill = Color.white.opacity(0x10 / 255.0)
/// Default (idle) icon button fill — subtle glass wash, between transparent and hover.
private let iconButtonIdleFill = Color.white.opacity(0.04)

/// Primary gradient CTA per `docs/03_COMPONENTS.md` §PrimaryButton —
/// `+ New`, `Protect this time`, `Generate plan`, etc.
///
/// 32 pt tall, accent gradient fill, subtle white stroke, and a primary glow.
public struct LiquidPrimaryButton: View {

    public let title: String
    public let systemImage: String?
    public let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(DS.FontToken.button)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .padding(.horizontal, DS.Space.m)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DS.ColorToken.accentPrimary, DS.ColorToken.accentPrimaryHover],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: DS.ColorToken.accentPrimary.opacity(0.30), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Square glass icon button per `docs/03_COMPONENTS.md` §IconButton.
///
/// 30 pt square, soft glass fill, brighter on hover, `glassSelected` fill
/// when active.
public struct LiquidIconButton: View {

    public let systemImage: String
    public let isSelected: Bool
    public let action: () -> Void

    @State private var hovering = false

    public init(systemImage: String, isSelected: Bool = false, action: @escaping () -> Void = {}) {
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    private var fill: Color {
        if isSelected { return DS.ColorToken.glassSelected }
        return hovering ? iconButtonHoverFill : iconButtonIdleFill
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(fill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
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
