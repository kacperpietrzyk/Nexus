import Foundation

/// Shared constants for the IPC bridge between Nexus.app and the nexus-mcp sidecar.
public enum AgentServiceConstants {
    /// App Group shared by NexusMac and the sidecar. Both are members, so both can
    /// reach files (incl. the unix-domain socket) inside its container.
    public static let appGroupIdentifier = "group.com.kacperpietrzyk.Nexus"

    /// Unix-domain socket file name inside the App Group container. The running app
    /// listens here; the sidecar connects. Kept short so the absolute path stays
    /// within sockaddr_un.sun_path (104 bytes on Darwin).
    public static let socketFileName = "agent.sock"

    /// Current protocol version. Sidecar checks at handshake.
    public static let protocolVersion = "1.0"

    /// UserDefaults key gating the listener.
    public static let mcpEnabledKey = "nexus.mcp.enabled"

    /// Absolute URL of the agent socket inside the App Group container, or nil if
    /// the container is unavailable (e.g. entitlement missing).
    public static func socketURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(socketFileName, isDirectory: false)
    }
}
