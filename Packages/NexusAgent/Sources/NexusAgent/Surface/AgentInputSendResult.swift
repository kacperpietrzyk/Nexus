public enum AgentInputSendResult: Sendable, Equatable {
    case accepted
    case rejected(String?)
}
