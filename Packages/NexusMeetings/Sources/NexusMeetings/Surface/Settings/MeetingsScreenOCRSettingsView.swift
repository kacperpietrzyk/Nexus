import NexusCore
import NexusUI
import SwiftUI

/// Opt-in toggle for shared-window screen OCR during recording (spec §7 / I4).
///
/// Default OFF: `@AppStorage` reads `false` for an unset key, so a fresh install
/// never captures the screen until the user explicitly enables it here. Bound to
/// the shared app-group defaults (`store: .nexusGroup`) so the recording helper
/// process — which actually performs the capture — reads the same value the UI
/// writes. Without `store: .nexusGroup` the toggle would silently no-op (UI writes
/// standard defaults, helper reads the group).
public struct MeetingsScreenOCRSettingsView: View {
    @AppStorage(MeetingsSettingsKeys.screenOCREnabled, store: .nexusGroup)
    private var screenOCREnabled = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            LiquidGlassCard("Screen context") {
                HStack {
                    Text("Capture shared-window text")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $screenOCREnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(minHeight: 44)
            }

            Text(
                "When on, the text of the window you share in a meeting is read "
                    + "on-device and added as context to the summary. Only the recognized "
                    + "text is used — no screenshots are ever saved. Off by default."
            )
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
