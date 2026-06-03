import Foundation

/// Mirrored from `NexusAgentTools.AgentServiceConstants` (the sidecar stays thin
/// and does not link the app's tool package).
enum AgentServiceConstants {
    static let appGroupIdentifier = "group.com.kacperpietrzyk.Nexus"
    static let socketFileName = "agent.sock"
    static let protocolVersion = "1.0"

    static func socketURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(socketFileName, isDirectory: false)
    }
}
