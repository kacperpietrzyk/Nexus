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

private final class MutablePermissionProbe: PermissionProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var value: MeetingsPermissionsReadiness
    init(_ value: MeetingsPermissionsReadiness) { self.value = value }
    func set(_ newValue: MeetingsPermissionsReadiness) { lock.withLock { value = newValue } }
    func currentPermissions() -> MeetingsPermissionsReadiness { lock.withLock { value } }
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

    // MARK: - transient-loud gate / debounce

    private func microphoneState(_ vm: MeetingsReadinessViewModel) -> ReadinessRowState? {
        vm.sections
            .first { $0.id == .permissions }?
            .rows.first { $0.id == "permission.microphone" }?
            .state
    }

    /// Builds a VM whose live microphone permission is mutable, so a re-probe can
    /// transiently flip a calm row loud (the "flip" this fix debounces).
    private func makeGatedViewModel(
        probe: MutablePermissionProbe,
        writer: RecordingWriter,
        debounceInterval: Duration
    ) -> MeetingsReadinessViewModel {
        let fixed = Date()
        let computer = MeetingsReadinessComputer(
            permissions: probe,
            models: StubModelProbe(
                value: MeetingsModelID.allCases.map { ModelReadiness(id: $0, sizeBytes: 1, state: .ready) }
            ),
            environment: StubEnvironmentProbe(value: .init(macOSCompatible: true, autoRecordEnabled: true)),
            clock: { fixed }
        )
        return MeetingsReadinessViewModel(
            reader: FixedReader(snapshot: nil),
            writer: writer,
            computer: computer,
            prefetcher: RecordingPrefetcher(),
            requestMicrophoneAccess: { $0(true) },
            openAccessibilitySettings: {},
            mapper: ReadinessRowMapper(stalenessThreshold: 120),
            now: { fixed },
            post: { _ in },
            debounceInterval: debounceInterval
        )
    }

    @Test("a transient calm→loud re-probe is held, not surfaced immediately")
    func transientLoudIsHeld() {
        let probe = MutablePermissionProbe(
            .init(microphone: .granted, accessibility: .granted, audioCapture: .granted)
        )
        let vm = makeGatedViewModel(probe: probe, writer: RecordingWriter(), debounceInterval: .seconds(10))

        vm.refresh()
        #expect(microphoneState(vm) == .ok)

        // Simulate the mid-toggle re-probe catching a transient `.notDetermined`.
        probe.set(.init(microphone: .notDetermined, accessibility: .granted, audioCapture: .granted))
        vm.refresh()

        // Held: the panel keeps the calm state instead of flipping to a loud card.
        #expect(microphoneState(vm) == .ok)
    }

    @Test("a settled needs-setup state surfaces its loud card after the debounce")
    func settledNeedsSetupSurfaces() async {
        let probe = MutablePermissionProbe(
            .init(microphone: .granted, accessibility: .granted, audioCapture: .granted)
        )
        let writer = RecordingWriter()
        let vm = makeGatedViewModel(probe: probe, writer: writer, debounceInterval: .milliseconds(20))

        vm.refresh()  // write #1
        probe.set(.init(microphone: .notDetermined, accessibility: .granted, audioCapture: .granted))
        vm.refresh()  // write #2 (held)
        #expect(microphoneState(vm) == .ok)  // held first

        // The state stays loud → after the debounced re-probe (write #3) it surfaces.
        await wait { writer.written.count >= 3 }
        #expect(microphoneState(vm) == .warning)
    }

    @Test("a transient that clears before the debounce never surfaces the loud card")
    func transientThatClearsNeverSurfaces() async {
        let probe = MutablePermissionProbe(
            .init(microphone: .granted, accessibility: .granted, audioCapture: .granted)
        )
        let writer = RecordingWriter()
        let vm = makeGatedViewModel(probe: probe, writer: writer, debounceInterval: .milliseconds(20))

        vm.refresh()  // write #1
        probe.set(.init(microphone: .notDetermined, accessibility: .granted, audioCapture: .granted))
        vm.refresh()  // write #2 (held)
        #expect(microphoneState(vm) == .ok)

        // Transient clears before the debounced re-probe fires.
        probe.set(.init(microphone: .granted, accessibility: .granted, audioCapture: .granted))

        // Wait for the debounced re-probe (write #3) to run.
        await wait { writer.written.count >= 3 }
        #expect(microphoneState(vm) == .ok)  // never flipped loud
    }

    @Test("a genuine needs-setup state on first render surfaces immediately")
    func firstRenderNeedsSetupSurfacesImmediately() {
        let probe = MutablePermissionProbe(
            .init(microphone: .notDetermined, accessibility: .granted, audioCapture: .granted)
        )
        let vm = makeGatedViewModel(probe: probe, writer: RecordingWriter(), debounceInterval: .seconds(10))

        vm.refresh()

        // No prior calm reading → not a regression → real setup prompt shows now.
        #expect(microphoneState(vm) == .warning)
    }

    // MARK: - introducesLoudRegression (pure)

    private func section(_ id: ReadinessSectionID, _ rows: [ReadinessRow]) -> [ReadinessSection] {
        [ReadinessSection(id: id, title: "t", rows: rows)]
    }

    private func row(_ id: String, _ state: ReadinessRowState) -> ReadinessRow {
        ReadinessRow(id: id, title: id, detail: nil, state: state, action: nil)
    }

    @Test("calm→loud is a regression")
    func calmToLoudIsRegression() {
        let old = section(.permissions, [row("a", .ok)])
        let new = section(.permissions, [row("a", .warning)])
        #expect(MeetingsReadinessViewModel.introducesLoudRegression(from: old, to: new))
    }

    @Test("already-loud→loud is not a regression")
    func loudToLoudIsNotRegression() {
        let old = section(.permissions, [row("a", .error)])
        let new = section(.permissions, [row("a", .warning)])
        #expect(!MeetingsReadinessViewModel.introducesLoudRegression(from: old, to: new))
    }

    @Test("first render (no prior rows) is not a regression")
    func firstRenderIsNotRegression() {
        let new = section(.permissions, [row("a", .error)])
        #expect(!MeetingsReadinessViewModel.introducesLoudRegression(from: [], to: new))
    }

    @Test("calm→calm is not a regression")
    func calmToCalmIsNotRegression() {
        let old = section(.permissions, [row("a", .ok)])
        let new = section(.permissions, [row("a", .info)])
        #expect(!MeetingsReadinessViewModel.introducesLoudRegression(from: old, to: new))
    }
}
