#if os(macOS)
import SwiftUI

/// Two-pane macOS Settings view — left category rail + right detail pane.
///
/// Mounted as a direct `ContentView.destinationMain` destination (Task 9).
/// For now, build + lint only; not wired into the shell yet.
///
/// Theme preference and advanced-toggle are stored in `UserDefaults` via
/// `@AppStorage`, identical keys and defaults to `NexusSettingsView.macGeneralSection`
/// so behaviour is unchanged when this replaces the legacy Settings window.
public struct LiquidSettingsView: View {
    @Environment(\.macSettingsDependencies) private var deps
    @State private var selected: SettingsCategory = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SettingsCategoryRail(selected: $selected)

            Divider()
                .overlay(DS.ColorToken.strokeHairline)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail pane

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                detailHeader(for: selected)
                detailContent(for: selected)
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 720, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Header (serif, Stats-idiom)

    private func detailHeader(for category: SettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Settings")
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .textCase(.uppercase)
                .tracking(1.4)

            Text(category.title)
                .font(DS.FontToken.displayLarge)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Per-category content

    @ViewBuilder
    private func detailContent(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            GeneralPanel()
        case .sync:
            LiquidGlassCard("Sync") {
                EmptyView()
            }
        case .tasks:
            LiquidGlassCard("Tasks") {
                EmptyView()
            }
        case .aiModels:
            LiquidGlassCard("AI & Models") {
                EmptyView()
            }
        case .meetings:
            LiquidGlassCard("Meetings") {
                EmptyView()
            }
        case .advanced:
            LiquidGlassCard("Advanced") {
                EmptyView()
            }
        case .about:
            LiquidGlassCard("About") {
                EmptyView()
            }
        }
    }
}

// MARK: - General panel

/// Theme picker + Advanced toggle panel.
///
/// Bindings mirror `NexusSettingsView.macGeneralSection` exactly:
/// `@AppStorage(NexusPreferences.Keys.theme)` → `String` raw-value,
/// `@AppStorage(NexusPreferences.Keys.advancedEnabled)` → `Bool`.
private struct GeneralPanel: View {
    @AppStorage(NexusPreferences.Keys.theme)
    private var theme: String = NexusTheme.amberDark.rawValue

    @AppStorage(NexusPreferences.Keys.advancedEnabled)
    private var advancedEnabled: Bool = false

    var body: some View {
        LiquidGlassCard("General") {
            VStack(spacing: 0) {
                // Theme row
                HStack {
                    Text("Theme")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Picker("Theme", selection: $theme) {
                        ForEach(NexusTheme.allCases, id: \.rawValue) { value in
                            Text(label(for: value)).tag(value.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text("Light mode arrives once the base tokens stabilize.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                // Advanced toggle row
                HStack {
                    Text("Show advanced features")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $advancedEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text("Reveals external access and advanced cloud-provider settings.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)
            }
        }
    }

    private func label(for theme: NexusTheme) -> String {
        switch theme {
        case .amberDark: return "Dark"
        }
    }
}

// MARK: - Preview

#Preview("LiquidSettingsView") {
    LiquidSettingsView()
        .environment(\.macSettingsDependencies, .empty)
        .frame(width: 860, height: 600)
        .background(DS.ColorToken.backgroundApp)
}
#endif
