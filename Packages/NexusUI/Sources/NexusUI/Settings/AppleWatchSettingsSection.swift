#if os(iOS)
import SwiftUI

/// iOS-only section pointing the user to the Watch app for managing Apple Watch
/// task reminder permissions. Mac doesn't pair with Apple Watch, so the section
/// is iOS-gated rather than `!os(watchOS)`.
public struct AppleWatchSettingsSection: View {
    public init() {}

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Powiadomienia o zadaniach")
                    .font(.headline)
                Text(
                    "Uprawnienia konfigurujesz w aplikacji Watch na iPhone — "
                        + "Powiadomienia → Nexus."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            nexusSettingsSectionHeader("Apple Watch")
        }
    }
}
#endif
