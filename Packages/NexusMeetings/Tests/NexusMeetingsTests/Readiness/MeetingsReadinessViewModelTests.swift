import Foundation
import Testing

@testable import NexusMeetings

private struct FixedReader: MeetingsReadinessReading {
    let snapshot: MeetingsReadinessSnapshot?
    func read() -> MeetingsReadinessSnapshot? { snapshot }
}

private final class RecordingWriter: MeetingsReadinessWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _written: [MeetingsReadinessSnapshot] = []
    var written: [MeetingsReadinessSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return _written
    }
    func write(_ snapshot: MeetingsReadinessSnapshot) {
        lock.lock()
        _written.append(snapshot)
        lock.unlock()
    }
}

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

private actor RecordingPrefetcher: MeetingsModelPrefetching {
    private(set) var requested: [MeetingsModelID] = []
    func prefetch(_ id: MeetingsModelID, progress: @Sendable @escaping (Double) -> Void) async throws {
        requested.append(id)
        progress(1.0)
    }
}

private final class PostLog {
    var names: [Notification.Name] = []
}

@MainActor
@Suite("MeetingsReadinessViewModel")
struct MeetingsReadinessViewModelTests {
    private func readySnapshot(
        microphone: PermissionState = .granted,
        models: ModelDownloadState = .ready
    ) -> MeetingsReadinessSnapshot {
        MeetingsReadinessSnapshot(
            permissions: .init(microphone: microphone, accessibility: .granted, audioCapture: .granted),
            models: MeetingsModelID.allCases.map { ModelReadiness(id: $0, sizeBytes: 1, state: models) },
            environment: .init(macOSCompatible: true, autoRecordEnabled: true),
            lastUpdated: Date()
        )
    }

    private func computer(returning snapshot: MeetingsReadinessSnapshot) -> MeetingsReadinessComputer {
        MeetingsReadinessComputer(
            permissions: StubPermissionProbe(value: snapshot.permissions),
            models: StubModelProbe(value: snapshot.models),
            environment: StubEnvironmentProbe(value: snapshot.environment),
            clock: { snapshot.lastUpdated }
        )
    }

    private func makeViewModel(
        snapshot: MeetingsReadinessSnapshot,
        writer: RecordingWriter = RecordingWriter(),
        prefetcher: any MeetingsModelPrefetching = RecordingPrefetcher(),
        micRequester: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void = { $0(true) },
        log: PostLog = PostLog()
    ) -> MeetingsReadinessViewModel {
        MeetingsReadinessViewModel(
            reader: FixedReader(snapshot: snapshot),
            writer: writer,
            computer: computer(returning: snapshot),
            prefetcher: prefetcher,
            requestMicrophoneAccess: micRequester,
            openAccessibilitySettings: {},
            mapper: ReadinessRowMapper(stalenessThreshold: 120),
            now: { snapshot.lastUpdated },
            post: { name in log.names.append(name) }
        )
    }

    // MARK: - refresh() recomputes in-process and persists

    @Test("refresh() recomputes from the in-process computer and persists a snapshot")
    func refreshRecomputesAndPersists() {
        let writer = RecordingWriter()
        let vm = makeViewModel(snapshot: readySnapshot(), writer: writer)

        vm.refresh()

        #expect(vm.sections.contains { $0.id == .permissions })
        #expect(writer.written.count == 1)
    }

    @Test("refresh() does not post over the helper channel")
    func refreshDoesNotPost() {
        let log = PostLog()
        let vm = makeViewModel(snapshot: readySnapshot(), log: log)

        vm.refresh()

        #expect(log.names.isEmpty)
    }

    // MARK: - microphone request runs in-process (no helper post)

    @Test("perform(.requestMicrophone) invokes the in-process requester, not the helper post")
    func requestMicrophoneRunsInProcess() {
        final class Flag: @unchecked Sendable {
            let lock = NSLock()
            var called = false
        }
        let flag = Flag()
        let log = PostLog()
        let vm = makeViewModel(
            snapshot: readySnapshot(microphone: .notDetermined),
            micRequester: { completion in
                flag.lock.lock()
                flag.called = true
                flag.lock.unlock()
                completion(true)
            },
            log: log
        )

        vm.perform(.requestMicrophone)

        flag.lock.lock()
        let called = flag.called
        flag.lock.unlock()
        #expect(called)
        #expect(!log.names.contains(MeetingsReadinessNotification.requestPermissions))
    }

    // MARK: - downloads run in-process via the prefetcher

    private func wait(
        until predicate: @escaping @Sendable () async -> Bool,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test("perform(.downloadModel) drives the in-process prefetcher for that model")
    func downloadModelInvokesPrefetcher() async {
        let prefetcher = RecordingPrefetcher()
        let vm = makeViewModel(snapshot: readySnapshot(models: .absent), prefetcher: prefetcher)

        vm.perform(.downloadModel(.parakeet))
        await wait { await prefetcher.requested == [.parakeet] }

        let requested = await prefetcher.requested
        #expect(requested == [.parakeet])
    }

    @Test("perform(.downloadAllModels) drives the prefetcher for every model")
    func downloadAllInvokesPrefetcher() async {
        let prefetcher = RecordingPrefetcher()
        let vm = makeViewModel(snapshot: readySnapshot(models: .absent), prefetcher: prefetcher)

        vm.perform(.downloadAllModels)
        await wait { await Set(prefetcher.requested) == Set(MeetingsModelID.allCases) }

        let requested = await prefetcher.requested
        #expect(Set(requested) == Set(MeetingsModelID.allCases))
    }

    @Test("downloadModel does NOT post over the helper channel")
    func downloadDoesNotPost() async {
        let log = PostLog()
        let prefetcher = RecordingPrefetcher()
        let vm = makeViewModel(snapshot: readySnapshot(models: .absent), prefetcher: prefetcher, log: log)

        vm.perform(.downloadAllModels)
        await wait { await Set(prefetcher.requested) == Set(MeetingsModelID.allCases) }

        #expect(!log.names.contains(MeetingsReadinessNotification.downloadModels))
    }

    // MARK: - helper-only actions still cross to the helper

    @Test("perform(.openAccessibilitySettings) posts requestPermissions as a fallback")
    func accessibilityPostsToHelper() {
        let log = PostLog()
        let vm = makeViewModel(snapshot: readySnapshot(), log: log)

        vm.perform(.openAccessibilitySettings)

        #expect(log.names.contains(MeetingsReadinessNotification.requestPermissions))
    }

    @Test("perform(.startHelper) posts refreshReadiness")
    func startHelperPosts() {
        let log = PostLog()
        let vm = makeViewModel(snapshot: readySnapshot(), log: log)

        vm.perform(.startHelper)

        #expect(log.names.contains(MeetingsReadinessNotification.refreshReadiness))
    }

    @Test("perform(.info) posts nothing")
    func infoPostsNothing() {
        let log = PostLog()
        let vm = makeViewModel(snapshot: readySnapshot(), log: log)

        vm.perform(.info("some message"))

        #expect(log.names.isEmpty)
    }
}
