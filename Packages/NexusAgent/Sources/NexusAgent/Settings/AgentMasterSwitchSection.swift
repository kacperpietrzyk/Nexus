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
        LiquidGlassCard("Master Switch") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Enable Nexus Agent")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(minHeight: 44)
                helperText(
                    enabled
                        ? "Chat, briefs and tool calls are active."
                        : "Chat is hidden; schedules are paused. Storage stays."
                )
                Divider()
                    .overlay(DS.ColorToken.strokeHairline)
                HStack {
                    Text("Vacation Mode")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $vacationMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(minHeight: 44)
                helperText("Pauses scheduled runs.")
            }
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DS.Space.s)
    }
}
