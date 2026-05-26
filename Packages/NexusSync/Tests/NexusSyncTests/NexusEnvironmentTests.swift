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
