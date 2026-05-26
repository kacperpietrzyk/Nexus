import SwiftUI

#if !os(watchOS)

/// Theme + locale + UI density. Phase 0f only ships theme (Amber dark only) — slot reserved
/// for future light mode + locale overrides. The Advanced toggle lives here so it remains
/// visible even when advanced-only sections are hidden.
public struct GeneralSettingsSection: View {
    @AppStorage(NexusPreferences.Keys.theme) private var theme: String = NexusTheme.amberDark.rawValue
    @AppStorage(NexusPreferences.Keys.advancedEnabled) private var advancedEnabled: Bool = false

    public init() {}

    public var body: some View {
        Section {
            Picker("Theme", selection: $theme) {
                ForEach(NexusTheme.allCases, id: \.rawValue) { value in
                    Text(label(for: value)).tag(value.rawValue)
                }
            }
            .pickerStyle(.menu)
            Text("Light mode arrives once the base tokens stabilize.")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)

            Toggle("Show advanced features", isOn: $advancedEnabled)
            Text("Reveals external access and advanced cloud-provider settings.")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
        } header: {
            nexusSettingsSectionHeader("General")
        }
    }

    private func label(for theme: NexusTheme) -> String {
        switch theme {
        case .amberDark: return "Dark"
        }
    }
}

#endif
