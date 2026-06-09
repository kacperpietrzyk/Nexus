import Foundation
import Testing
@testable import NexusMeetings

@Suite("MeetingsReadinessStore")
struct MeetingsReadinessStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.meetings.readiness.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("write then read returns an equal snapshot; empty store returns nil")
    func writeRead() {
        let defaults = makeDefaults()
        let store = UserDefaultsMeetingsReadinessStore(defaults: defaults)
        #expect(store.read() == nil)

        let snapshot = MeetingsReadinessSnapshot(
            permissions: .init(microphone: .granted, accessibility: .notDetermined, audioCapture: .unknown),
            models: [ModelReadiness(id: .parakeet, sizeBytes: nil, state: .absent)],
            environment: .init(macOSCompatible: true, autoRecordEnabled: true),
            lastUpdated: Date(timeIntervalSince1970: 99)
        )
        store.write(snapshot)

        #expect(store.read() == snapshot)
    }
}
