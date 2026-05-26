import Foundation

/// Shared constants for the XPC bridge between Nexus.app and the nexus-mcp sidecar.
public enum AgentServiceConstants {
    /// Suffix appended after the team identifier prefix to form the Mach service name.
    /// Full name: "<TeamID>.\(machServiceSuffix)" where TeamID is read at runtime.
    public static let machServiceSuffix = "com.kacperpietrzyk.nexus.agent"

    /// Current XPC + tool-manifest protocol version. Sidecar checks at handshake.
    /// Bump major when XPC interface changes incompatibly.
    public static let protocolVersion = "1.0"

    /// UserDefaults key gating the listener.
    public static let mcpEnabledKey = "nexus.mcp.enabled"

    /// Computes the runtime Mach service name. NexusMac uses `Bundle.main` (its own
    /// embedded provisioning); sidecar reads the team identifier prefix from its
    /// own bundle which shares the team after codesign.
    public static func machServiceName(from bundle: Bundle = .main) -> String {
        let prefix = (bundle.infoDictionary?["TeamIdentifierPrefix"] as? String) ?? ""
        return "\(prefix)\(machServiceSuffix)"
    }
}

/// Compatibility forwarding API for early scaffold callers.
public func machServiceName(from bundle: Bundle = .main) -> String {
    AgentServiceConstants.machServiceName(from: bundle)
}
