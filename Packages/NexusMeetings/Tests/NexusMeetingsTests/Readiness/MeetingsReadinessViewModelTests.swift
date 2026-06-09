import Foundation
import Testing
@testable import NexusMeetings

private struct FixedReader: MeetingsReadinessReading {
    let snapshot: MeetingsReadinessSnapshot?
    func read() -> MeetingsReadinessSnapshot? { snapshot }
}

@MainActor
@Suite("MeetingsReadinessViewModel")
struct MeetingsReadinessViewModelTests {
    @Test("refresh loads sections from the store snapshot")
    func refreshLoads() {
        let snapshot = MeetingsReadinessSnapshot(
            permissions: .init(microphone: .granted, accessibility: .granted, audioCapture: .granted),
            models: MeetingsModelID.allCases.map { ModelReadiness(id: $0, sizeBytes: 1, state: .ready) },
            environment: .init(macOSCompatible: true, autoRecordEnabled: true),
            lastUpdated: Date()
        )
        var posted: [Notification.Name] = []
        let viewModel = MeetingsReadinessViewModel(
            reader: FixedReader(snapshot: snapshot),
            mapper: ReadinessRowMapper(stalenessThreshold: 120),
            now: { Date() },
            post: { name in posted.append(name) }
        )

        viewModel.refresh()

        #expect(viewModel.sections.contains { $0.id == .permissions })
        viewModel.perform(.requestMicrophone)
        #expect(posted.contains(MeetingsReadinessNotification.requestPermissions))
        viewModel.perform(.downloadAllModels)
        #expect(posted.contains(MeetingsReadinessNotification.downloadModels))
    }
}
