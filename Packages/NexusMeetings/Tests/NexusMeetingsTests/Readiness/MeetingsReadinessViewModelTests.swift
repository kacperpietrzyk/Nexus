import Foundation
import Testing
@testable import NexusMeetings

private struct FixedReader: MeetingsReadinessReading {
    let snapshot: MeetingsReadinessSnapshot?
    func read() -> MeetingsReadinessSnapshot? { snapshot }
}

private final class PostLog {
    var names: [Notification.Name] = []
}

@MainActor
@Suite("MeetingsReadinessViewModel")
struct MeetingsReadinessViewModelTests {
    private func makeViewModel(
        snapshot: MeetingsReadinessSnapshot? = nil,
        log: PostLog
    ) -> MeetingsReadinessViewModel {
        MeetingsReadinessViewModel(
            reader: FixedReader(snapshot: snapshot),
            mapper: ReadinessRowMapper(stalenessThreshold: 120),
            now: { Date() },
            post: { name in log.names.append(name) }
        )
    }

    private func makeReadySnapshot() -> MeetingsReadinessSnapshot {
        MeetingsReadinessSnapshot(
            permissions: .init(
                microphone: .granted, accessibility: .granted, audioCapture: .granted),
            models: MeetingsModelID.allCases.map {
                ModelReadiness(id: $0, sizeBytes: 1, state: .ready)
            },
            environment: .init(macOSCompatible: true, autoRecordEnabled: true),
            lastUpdated: Date()
        )
    }

    // MARK: - refresh() is a pure read; it must NOT post refreshReadiness

    @Test("refresh() does not post refreshReadiness")
    func refreshDoesNotPost() {
        let log = PostLog()
        let vm = makeViewModel(snapshot: makeReadySnapshot(), log: log)

        vm.refresh()

        #expect(!log.names.contains(MeetingsReadinessNotification.refreshReadiness))
    }

    @Test("refresh() loads sections from the store snapshot")
    func refreshLoadsSections() {
        let log = PostLog()
        let vm = makeViewModel(snapshot: makeReadySnapshot(), log: log)

        vm.refresh()

        #expect(vm.sections.contains { $0.id == .permissions })
    }

    // MARK: - requestHelperRefresh() posts refreshReadiness

    @Test("requestHelperRefresh() posts refreshReadiness")
    func requestHelperRefreshPosts() {
        let log = PostLog()
        let vm = makeViewModel(log: log)

        vm.requestHelperRefresh()

        #expect(log.names.contains(MeetingsReadinessNotification.refreshReadiness))
    }

    // MARK: - perform(_:) dispatches the correct notifications

    @Test("perform(.requestMicrophone) posts requestPermissions")
    func performRequestMicrophone() {
        let log = PostLog()
        let vm = makeViewModel(log: log)

        vm.perform(.requestMicrophone)

        #expect(log.names.contains(MeetingsReadinessNotification.requestPermissions))
    }

    @Test("perform(.downloadAllModels) posts downloadModels")
    func performDownloadAllModels() {
        let log = PostLog()
        let vm = makeViewModel(log: log)

        vm.perform(.downloadAllModels)

        #expect(log.names.contains(MeetingsReadinessNotification.downloadModels))
    }

    @Test("perform(.startHelper) posts refreshReadiness")
    func performStartHelper() {
        let log = PostLog()
        let vm = makeViewModel(log: log)

        vm.perform(.startHelper)

        #expect(log.names.contains(MeetingsReadinessNotification.refreshReadiness))
    }

    @Test("perform(.enableAutoRecord) posts refreshReadiness")
    func performEnableAutoRecord() {
        let log = PostLog()
        let vm = makeViewModel(log: log)

        vm.perform(.enableAutoRecord)

        #expect(log.names.contains(MeetingsReadinessNotification.refreshReadiness))
    }

    @Test("perform(.info) posts nothing")
    func performInfoPostsNothing() {
        let log = PostLog()
        let vm = makeViewModel(log: log)

        vm.perform(.info("some message"))

        #expect(log.names.isEmpty)
    }
}
