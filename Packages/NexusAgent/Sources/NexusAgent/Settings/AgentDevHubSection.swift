import NexusUI
import SwiftUI

public struct AgentDevHubSection: View {
    public let context: AgentSettingsContext

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        Section("Dev Hub") {
            Text(
                "Git, GitHub, Linear, and Xcode adapters land in the next release. "
                    + "The agent will read repo + PR + issue + build state to brief project work."
            )
            .font(.caption)
            .foregroundStyle(NexusColor.Text.muted)
        }
    }
}
