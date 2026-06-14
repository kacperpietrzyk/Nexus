import SwiftUI

/// Flat Linear chrome for a pushed settings detail screen.
///
/// Replaces the native grouped-`Form` chrome and the floating system back
/// button with a custom header — a back affordance (`chevron.left`) + an `h3`
/// title — over a hairline seam, then a scrolling content region with s5 edge
/// padding. A screen wrapped in this reads continuous with `NexusSettingsCard`
/// content: no gray system grouping, no floating back button.
public struct NexusSettingsDetailContainer<Content: View>: View {

    public let title: String
    @ViewBuilder public let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsDetailEmbedded) private var embedded

    public init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        if embedded {
            // Embedded inside a host detail pane (Liquid two-pane macOS Settings)
            // that already supplies the back affordance, scrolling, and wallpaper.
            // Render the bare content: no custom header, no own `ScrollView`, no
            // opaque background (let the host glass/wallpaper show through), and no
            // `HiddenNativeChrome` (the host's `NavigationStack` owns chrome — see
            // `LiquidSettingsView`). Padding is preserved so the embedded sub-views
            // align with the host's surrounding cards.
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NexusSpacing.s5)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                NexusSettingsDivider()
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(NexusSpacing.s5)
                }
            }
            // Liquid re-skin (container level): DS app background (was the Linear
            // `Background.base`; near-identical value, family-correct token).
            .background(DS.ColorToken.backgroundApp)
            .modifier(HiddenNativeChrome())
        }
    }

    private var header: some View {
        HStack(spacing: NexusSpacing.s3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NexusColor.Text.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(title)
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.primary)

            Spacer(minLength: NexusSpacing.s4)
        }
        .padding(.horizontal, NexusSpacing.s5)
        .padding(.vertical, NexusSpacing.s3)
    }
}

/// Hides the native navigation chrome so only the custom header shows. The
/// modifiers diverge by platform: `navigationBarBackButtonHidden` is iOS-only,
/// `.toolbar(.hidden)` covers macOS.
private struct HiddenNativeChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        #else
        content
            .toolbar(.hidden)
        #endif
    }
}

/// When `true`, `NexusSettingsDetailContainer` renders its content chromeless —
/// without the custom back-button header or its own `ScrollView` — for embedding
/// inside a host detail pane that already scrolls and supplies navigation chrome
/// (the Liquid two-pane macOS Settings). Default `false` preserves the standalone
/// pushed-screen behaviour on iOS / legacy paths.
private struct SettingsDetailEmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var settingsDetailEmbedded: Bool {
        get { self[SettingsDetailEmbeddedKey.self] }
        set { self[SettingsDetailEmbeddedKey.self] = newValue }
    }
}

#Preview("Detail container") {
    NavigationStack {
        NexusSettingsDetailContainer(title: "Models") {
            VStack(alignment: .leading, spacing: NexusSpacing.s4) {
                nexusSettingsCardSectionHeader("On-device")
                NexusSettingsCard {
                    NexusSettingsRow("Qwen 2.5") {
                        Text("Installed")
                            .font(NexusType.bodySmall.weight(.medium))
                            .foregroundStyle(NexusColor.Text.secondary)
                    }
                }
            }
        }
    }
    .background(NexusColor.Background.base)
}
