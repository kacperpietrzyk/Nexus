import NexusUI
import SwiftUI

// swiftlint:disable:next inclusive_language
public struct AgentMasterSwitchSection: View {
    public let context: AgentSettingsContext
    @AppStorage(NexusPreferences.Keys.agentEnabled) private var enabled = true
    @AppStorage(NexusPreferences.Keys.agentVacationMode) private var vacationMode = false

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Master Switch")
            NexusSettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    NexusSettingsRow("Enable Nexus Agent") {
                        Toggle("", isOn: $enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    helperText(
                        enabled
                            ? "Chat, briefs and tool calls are active."
                            : "Chat is hidden; schedules are paused. Storage stays."
                    )
                    NexusSettingsDivider()
                    NexusSettingsRow("Vacation Mode") {
                        Toggle("", isOn: $vacationMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    helperText("Pauses scheduled runs.")
                }
            }
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(NexusType.caption)
            .foregroundStyle(NexusColor.Text.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NexusSpacing.s4)
            .padding(.bottom, NexusSpacing.s3)
    }
}
