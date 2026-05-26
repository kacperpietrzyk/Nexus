import NexusAgentToolsExtras

// Keeps the empty extension target buildable until concrete extras tools land.
enum NexusAgentToolsExtrasCompileCheck {
    static let version = NexusAgentToolsExtras.version
}
