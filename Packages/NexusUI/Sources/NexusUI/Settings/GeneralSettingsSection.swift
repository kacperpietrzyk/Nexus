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
            Picker("Motyw", selection: $theme) {
                ForEach(NexusTheme.allCases, id: \.rawValue) { value in
                    Text(label(for: value)).tag(value.rawValue)
                }
            }
            .pickerStyle(.menu)
            Text("Tryb jasny pojawi się po ustabilizowaniu bazowych tokenów.")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)

            Toggle("Pokaż zaawansowane funkcje", isOn: $advancedEnabled)
            Text("Odsłania dostęp zewnętrzny i zaawansowane ustawienia dostawców chmurowych.")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
        } header: {
            nexusSettingsSectionHeader("Ogólne")
        }
    }

    private func label(for theme: NexusTheme) -> String {
        switch theme {
        case .amberDark: return "Ciemny"
        }
    }
}

#endif
