import NexusUI
import SwiftUI

public struct AgentProviderRoutingSection: View {
    public let context: AgentSettingsContext

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s7) {
            VStack(alignment: .leading, spacing: NexusSpacing.s3) {
                nexusSettingsCardSectionHeader("AI routing")
                NexusSettingsCard {
                    Text(
                        "Agent uses the same local provider surface as the rest of Nexus. "
                            + "Apple Intelligence is active today; Phase 1l-MLX adds a local LLM "
                            + "for longer context without introducing network fallback."
                    )
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NexusSpacing.s4)
                }
            }

            AISettingsSection(liveData: context.aiLiveData)
        }
    }
}
