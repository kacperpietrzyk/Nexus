import SwiftUI

private struct AgentChatViewModelKey: EnvironmentKey {
    static let defaultValue: AgentChatViewModel? = nil
}

extension EnvironmentValues {
    public var agentChatViewModel: AgentChatViewModel? {
        get { self[AgentChatViewModelKey.self] }
        set { self[AgentChatViewModelKey.self] = newValue }
    }
}
