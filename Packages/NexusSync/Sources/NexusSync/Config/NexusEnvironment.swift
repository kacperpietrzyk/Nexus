import Foundation

/// Runtime feature switches read from process environment. Lets development run without an
/// active CloudKit container (Apple Developer Program activation pending) by defaulting
/// `cloudKitEnabled` to false until `NEXUS_CLOUDKIT_ENABLED=1` is set in the scheme env.
public struct NexusEnvironment: Sendable {
    public static let cloudKitEnabledKey = "NEXUS_CLOUDKIT_ENABLED"
    public static let containerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"

    private let rawCloudKitFlag: String?

    public init(processInfo: ProcessInfo) {
        self.rawCloudKitFlag = processInfo.environment[Self.cloudKitEnabledKey]
    }

    public static var current: NexusEnvironment {
        NexusEnvironment(processInfo: .processInfo)
    }

    public var cloudKitEnabled: Bool {
        guard let raw = rawCloudKitFlag?.lowercased() else { return false }
        return ["1", "true", "yes"].contains(raw)
    }

    public var cloudKitContainerIdentifier: String { Self.containerIdentifier }
}
