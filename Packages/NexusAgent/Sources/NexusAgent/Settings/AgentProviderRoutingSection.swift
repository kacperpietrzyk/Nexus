import NexusUI
import SwiftUI

public struct AgentProviderRoutingSection: View {
    public let context: AgentSettingsContext

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        SwiftUI.Section("AI routing") {
            Text(
                "Agent uses the same local provider surface as the rest of Nexus. "
                    + "Apple Intelligence is active today; Phase 1l-MLX adds a local LLM "
                    + "for longer context without introducing network fallback."
            )
            .font(.caption)
            .foregroundStyle(NexusColor.Text.muted)
        }

        AISettingsSection(liveData: context.aiLiveData)
    }
}
