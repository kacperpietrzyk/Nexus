import Foundation

/// Mirrored from `NexusAgentTools.AgentServiceConstants`.
///
/// The sidecar deliberately stays thin and does not import the app's tool
/// package, so this stable transport constant is duplicated.
enum AgentServiceConstants {
    static let machServiceSuffix = "com.kacperpietrzyk.nexus.agent"
    static let protocolVersion = "1.0"
}

func machServiceName(from bundle: Bundle = .main) -> String {
    let prefix = (bundle.infoDictionary?["TeamIdentifierPrefix"] as? String) ?? ""
    return "\(prefix)\(AgentServiceConstants.machServiceSuffix)"
}
