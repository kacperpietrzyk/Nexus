import NexusUI
import SwiftUI

public struct AgentDevHubSection: View {
    public let context: AgentSettingsContext

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Dev Hub")
            NexusSettingsCard {
                Text(
                    "Git, GitHub, Linear, and Xcode adapters land in the next release. "
                        + "The agent will read repo + PR + issue + build state to brief project work."
                )
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NexusSpacing.s4)
            }
        }
    }
}
