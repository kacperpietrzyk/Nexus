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
        Section("Master Switch") {
            Toggle("Enable Nexus Agent", isOn: $enabled)
                .toggleStyle(.switch)
            Text(
                enabled
                    ? "Chat, briefs and tool calls are active."
                    : "Chat is hidden; schedules are paused. Storage stays."
            )
            .font(.caption)
            .foregroundStyle(NexusColor.Text.muted)
            Toggle("Vacation Mode", isOn: $vacationMode)
                .toggleStyle(.switch)
            Text("Pauses scheduled runs.")
                .font(.caption)
                .foregroundStyle(NexusColor.Text.muted)
        }
    }
}
