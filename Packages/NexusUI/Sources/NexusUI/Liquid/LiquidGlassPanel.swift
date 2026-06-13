import SwiftUI

#if os(macOS)
import AppKit

private struct LiquidVisualEffectBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // Emphasized vibrancy brightens the material toward white — exactly the
        // milky frost we are removing. Keep it off; darkening is done by the
        // `baseGlaze` dark tint instead.
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.isEmphasized = false
    }
}
#endif

/// The liquid glass surface recipe — material sample, translucent dark tint,
/// rim light, inner glint, absorption shade, and soft separation shadow.
///
/// This modifier is the single shared glass grammar. Screens should choose a
/// variant instead of rebuilding their own stacked overlays.
public struct LiquidGlassPanel: ViewModifier {

    /// Which glass tint the panel uses. Variants map 1:1 onto the
    /// `DS.ColorToken.glass*` tokens.
    public enum Variant: Sendable {
        case shell
        case sidebar
        case toolbar
        case card
        case strong
        case selected
    }

    public let variant: Variant
    public let cornerRadius: CGFloat
    public let isHovering: Bool

    public init(variant: Variant, cornerRadius: CGFloat, isHovering: Bool = false) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.isHovering = isHovering
    }

    private var materialTint: Color {
        switch variant {
        case .shell: return DS.ColorToken.glassBase
        case .sidebar: return DS.ColorToken.glassSidebar
        case .toolbar: return DS.ColorToken.glassToolbar
        case .card: return isHovering ? DS.ColorToken.glassCardHover : DS.ColorToken.glassCard
        case .strong: return DS.ColorToken.glassStrong
        case .selected: return DS.ColorToken.glassSelected
        }
    }

    private var chromaWash: Color {
        switch variant {
        case .shell: return DS.ColorToken.accentBlue.opacity(0.004)
        case .sidebar: return DS.ColorToken.accentPrimary.opacity(0.014)
        case .toolbar: return DS.ColorToken.accentBlue.opacity(0.010)
        case .card: return DS.ColorToken.accentCyan.opacity(isHovering ? 0.012 : 0.004)
        case .strong: return DS.ColorToken.accentPrimary.opacity(0.026)
        case .selected: return DS.ColorToken.accentPrimary.opacity(0.090)
        }
    }

    private var highlightOpacity: Double {
        switch variant {
        case .shell: return 0.18
        case .sidebar: return 0.16
        case .toolbar: return 0.12
        case .card: return 0.11
        case .strong: return 0.13
        case .selected: return 0.20
        }
    }

    private var stroke: Color {
        if variant == .selected { return DS.ColorToken.strokeStrong }
        if isHovering { return DS.ColorToken.strokeDefault }
        switch variant {
        case .shell, .sidebar, .card, .toolbar:
            return DS.ColorToken.strokeHairline
        case .strong:
            return DS.ColorToken.strokeDefault
        case .selected:
            return DS.ColorToken.strokeStrong
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .card, .selected: return 12
        case .toolbar: return 12
        default: return 20
        }
    }

    private var shadowY: CGFloat {
        switch variant {
        case .card, .selected: return 5
        case .toolbar: return 5
        default: return 9
        }
    }

    private var accentShadow: Color {
        switch variant {
        case .selected:
            return DS.ColorToken.accentPrimary.opacity(0.22)
        case .sidebar:
            return DS.ColorToken.accentPrimary.opacity(0.035)
        case .shell:
            return DS.ColorToken.accentBlue.opacity(0.030)
        default:
            return .clear
        }
    }

    private var material: Material {
        switch variant {
        case .shell, .sidebar, .toolbar, .card, .selected:
            return .ultraThinMaterial
        case .strong:
            return .regularMaterial
        }
    }

    #if os(macOS)
    private var appKitBlendingMode: NSVisualEffectView.BlendingMode {
        switch variant {
        case .shell, .sidebar:
            return .behindWindow
        case .toolbar, .card, .strong, .selected:
            return .withinWindow
        }
    }
    #endif

    /// Dark navy tint laid directly over the blurred system material. This is
    /// what pulls the glass from a light/white frost down to the reference's
    /// dark, see-through tone. The desktop still reads through it (darkened +
    /// blurred), so the surface stays transparent and wallpaper-dependent — it
    /// just stops being milky.
    private var baseGlaze: Color {
        switch variant {
        case .shell:
            return Color(hex: 0x060A11, alpha: 0.22)
        case .sidebar:
            return Color(hex: 0x080F1A, alpha: 0.30)
        case .toolbar:
            return Color(hex: 0x080F1A, alpha: 0.26)
        case .card:
            return Color(hex: 0x080F1A, alpha: 0.34)
        case .strong:
            return Color(hex: 0x080F1A, alpha: 0.46)
        case .selected:
            return .clear
        }
    }

    #if os(macOS)
    private var appKitMaterial: NSVisualEffectView.Material {
        switch variant {
        case .shell:
            return .underWindowBackground
        case .sidebar:
            return .sidebar
        case .toolbar:
            return .headerView
        case .card:
            return .contentBackground
        case .strong:
            return .hudWindow
        case .selected:
            return .selection
        }
    }
    #endif

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background { glassFill(shape) }
            .overlay { glassBorder(shape) }
            .shadow(color: accentShadow, radius: variant == .selected ? 10 : 12, x: 0, y: 0)
            .shadow(
                color: Color.black.opacity(variant == .shell ? 0.22 : 0.12),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }

    /// The translucent body: dark tint over the blurred system material, then
    /// the soft sheen / chroma overlays that give it depth.
    @ViewBuilder
    private func glassFill(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(baseGlaze)
            .background {
                #if os(macOS)
                LiquidVisualEffectBackdrop(material: appKitMaterial, blendingMode: appKitBlendingMode)
                    .clipShape(shape)
                #else
                shape.fill(.clear).background(material, in: shape)
                #endif
            }
            .overlay(shape.fill(materialTint))
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(variant == .selected ? 0.05 : 0.024),
                                .clear,
                                Color.black.opacity(variant == .shell ? 0.030 : 0.052),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(variant == .shell ? 0.06 : 0.040), location: 0.0),
                                .init(color: Color.white.opacity(0.010), location: 0.26),
                                .init(color: .clear, location: 0.52),
                                .init(color: Color.black.opacity(variant == .shell ? 0.060 : 0.080), location: 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(
                shape
                    .fill(
                        RadialGradient(
                            colors: [chromaWash, .clear],
                            center: UnitPoint(x: 0.12, y: 0.08),
                            startRadius: 0,
                            endRadius: variant == .card ? 260 : 620
                        )
                    )
                    .blendMode(.screen)
            )
    }

    /// Single hairline boundary. The previous recipe stacked three strokes
    /// (border + screen highlight + multiply shade); adjacent / nested panels
    /// turned that into "lines next to lines". One border with a faint top-edge
    /// glint inside it keeps the glass read without the clutter.
    private func glassBorder(_ shape: RoundedRectangle) -> some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(highlightOpacity), stroke, stroke],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: variant == .selected ? 1.25 : 1
            )
    }
}

extension View {
    /// Applies the liquid glass surface recipe to any view.
    ///
    /// - Parameters:
    ///   - variant: the glass tint; defaults to `.card`.
    ///   - radius: corner radius; defaults to `DS.Radius.l` (16 pt — the card radius).
    ///   - isHovering: brightens the fill and stroke for hover feedback.
    public func liquidGlass(
        _ variant: LiquidGlassPanel.Variant = .card,
        radius: CGFloat = DS.Radius.l,
        isHovering: Bool = false
    ) -> some View {
        modifier(LiquidGlassPanel(variant: variant, cornerRadius: radius, isHovering: isHovering))
    }
}
