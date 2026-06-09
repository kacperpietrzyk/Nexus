import Foundation
import Testing
@testable import NexusMeetings

private struct StubAutoRecord: HelperAutoRecordStoring {
    let enabled: Bool
    func isEnabled() -> Bool { enabled }
    func save(enabled: Bool) {}
}

@Suite("LiveEnvironmentProbe")
struct LiveEnvironmentProbeTests {
    @Test("reports macOS compatibility from the injected flag and auto-record from the store")
    func reports() {
        let probe = LiveEnvironmentProbe(
            autoRecordStore: StubAutoRecord(enabled: true),
            isMacOSCompatible: { true }
        )
        let environment = probe.currentEnvironment()
        #expect(environment.macOSCompatible)
        #expect(environment.autoRecordEnabled)
    }
}
