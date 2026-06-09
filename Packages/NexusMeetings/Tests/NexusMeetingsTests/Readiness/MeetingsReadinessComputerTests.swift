import Foundation
import Testing
@testable import NexusMeetings

private struct StubPermissionProbe: PermissionProbing {
    let value: MeetingsPermissionsReadiness
    func currentPermissions() -> MeetingsPermissionsReadiness { value }
}

private struct StubModelProbe: ModelProbing {
    let value: [ModelReadiness]
    func currentModels() -> [ModelReadiness] { value }
}

private struct StubEnvironmentProbe: EnvironmentProbing {
    let value: MeetingsEnvironmentReadiness
    func currentEnvironment() -> MeetingsEnvironmentReadiness { value }
}

@Suite("MeetingsReadinessComputer")
struct MeetingsReadinessComputerTests {
    @Test("composes a snapshot from the three probes and stamps the clock")
    func composes() {
        let computer = MeetingsReadinessComputer(
            permissions: StubPermissionProbe(value: .init(microphone: .granted, accessibility: .granted, audioCapture: .unknown)),
            models: StubModelProbe(value: [ModelReadiness(id: .parakeet, sizeBytes: 10, state: .ready)]),
            environment: StubEnvironmentProbe(value: .init(macOSCompatible: true, autoRecordEnabled: true)),
            clock: { Date(timeIntervalSince1970: 42) }
        )

        let snapshot = computer.snapshot()

        #expect(snapshot.permissions.microphone == .granted)
        #expect(snapshot.models.count == 1)
        #expect(snapshot.environment.autoRecordEnabled)
        #expect(snapshot.lastUpdated == Date(timeIntervalSince1970: 42))
    }
}
