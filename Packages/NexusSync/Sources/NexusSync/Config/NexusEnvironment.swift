import Foundation

/// Runtime feature switch for CloudKit sync.
///
/// History: this originally defaulted `cloudKitEnabled` to `false` and only flipped on when
/// `NEXUS_CLOUDKIT_ENABLED=1` was set in the Xcode scheme env — a dev convenience while the
/// Apple Developer Program activation was pending. That gate is **broken for distribution**:
/// scheme environment variables are injected ONLY when launching from Xcode. Archived /
/// TestFlight / App Store builds have no such variable, so `ProcessInfo.environment` never
/// contains it and sync was permanently off on every distributed build, on every device.
///
/// New behaviour: the explicit env var still wins (so a local debug run can force either
/// state), but the *default* is now build-configuration driven — OFF in DEBUG (keeps local
/// dev off CloudKit unless explicitly opted in) and ON in release builds so TestFlight /
/// App Store users actually sync.
///
/// IMPORTANT — enabling sync end-to-end also requires (NOT covered by this flag):
///   1. `aps-environment` entitlement + `remote-notification` in `UIBackgroundModes`
///      (CloudKit mirroring needs silent pushes), and the Push capability on the App ID.
///   2. The CloudKit **Production** schema deployed (promote from Development in the
///      CloudKit Dashboard) — TestFlight/App Store use the Production environment.
///   3. A Release-build smoke with a real iCloud account before uploading.
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
        if let raw = rawCloudKitFlag?.lowercased() {
            return ["1", "true", "yes"].contains(raw)
        }
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    public var cloudKitContainerIdentifier: String { Self.containerIdentifier }
}
