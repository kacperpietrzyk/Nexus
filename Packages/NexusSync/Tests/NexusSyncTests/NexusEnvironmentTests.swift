import Foundation
import Testing

@testable import NexusSync

/// Serialized because every test mutates the process-global `NEXUS_CLOUDKIT_ENABLED`
/// env var; running them in parallel races and produces flaky failures.
@Suite(.serialized)
struct NexusEnvironmentTests {
    @Test func defaultIsCloudKitDisabled() {
        defer { unsetenv(NexusEnvironment.cloudKitEnabledKey) }
        setenv(NexusEnvironment.cloudKitEnabledKey, "", 1)
        let env = NexusEnvironment(processInfo: ProcessInfo.processInfo)
        #expect(env.cloudKitEnabled == false)
    }

    /// When the env var is entirely absent (the real distributed-build case — scheme env
    /// vars are NOT injected into archived/TestFlight builds), the default is build-config
    /// driven: off in DEBUG, on in release. This locks the fix for the bug where every
    /// TestFlight build reported sync "disabled (dev)" because the env var never existed.
    @Test func unsetFallsBackToBuildConfigurationDefault() {
        unsetenv(NexusEnvironment.cloudKitEnabledKey)
        let env = NexusEnvironment(processInfo: ProcessInfo.processInfo)
        #if DEBUG
        #expect(env.cloudKitEnabled == false, "DEBUG builds default CloudKit off")
        #else
        #expect(env.cloudKitEnabled == true, "Release builds default CloudKit on")
        #endif
    }

    @Test func truthyValuesEnableCloudKit() {
        defer { unsetenv(NexusEnvironment.cloudKitEnabledKey) }
        for value in ["1", "true", "TRUE", "yes", "YES"] {
            setenv(NexusEnvironment.cloudKitEnabledKey, value, 1)
            let env = NexusEnvironment(processInfo: ProcessInfo.processInfo)
            #expect(env.cloudKitEnabled == true, "Expected '\(value)' to enable CloudKit")
        }
    }

    @Test func containerIdentifier_isStable() {
        let env = NexusEnvironment(processInfo: ProcessInfo.processInfo)
        #expect(env.cloudKitContainerIdentifier == "iCloud.com.kacperpietrzyk.Nexus")
    }
}
