import Foundation
import Testing

@testable import NexusMeetings

#if os(macOS)
@preconcurrency import ServiceManagement

@MainActor
@Test func helperViewModelInitialStateMatchesStubManager() {
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .enabled },
        registrar: StubRegistrar()
    )

    vm.refresh()

    #expect(vm.statusLabel.contains("enabled") || vm.statusLabel.contains("Enabled"))
}

@MainActor
@Test func refreshSetsEnabledStateFromProviderStatus() {
    var status = SMAppService.Status.enabled
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { status },
        registrar: StubRegistrar()
    )

    vm.refresh()
    #expect(vm.isEnabled)

    status = .notRegistered
    vm.refresh()
    #expect(!vm.isEnabled)
}

@MainActor
@Test func enablingHelperRegistersViaRegistrarAndRequestsMicInProcess() {
    let registrar = RecordingRegistrar()
    let preferences = RecordingAutoRecordStore()
    let micFlag = MicRequestFlag()
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .enabled },
        registrar: registrar,
        preferenceStore: preferences,
        requestMicrophoneAccess: { completion in
            micFlag.markCalled()
            completion(true)
        }
    )

    vm.toggle(enabled: true)

    #expect(registrar.registerCallCount == 1)
    #expect(registrar.unregisterCallCount == 0)
    #expect(preferences.savedValues == [true])
    // Microphone is requested IN-PROCESS, not via the sandboxed helper.
    #expect(micFlag.wasCalled)
}

private final class MicRequestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    var wasCalled: Bool { lock.withLock { called } }
    func markCalled() { lock.withLock { called = true } }
}

@MainActor
@Test func enablingHelperRefreshesReadinessAfterMicCompletion() {
    let posts = PostRecorder()
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .enabled },
        registrar: RecordingRegistrar(),
        preferenceStore: RecordingAutoRecordStore(),
        requestMicrophoneAccess: { completion in completion(true) },
        post: { posts.append($0) }
    )

    vm.toggle(enabled: true)

    // The mic-completion path must re-probe readiness (so the panel doesn't
    // stick on the transient mid-prompt state), plus the best-effort helper nudge.
    #expect(posts.names.contains(MeetingsReadinessNotification.readinessDidChange))
    #expect(posts.names.contains(MeetingsReadinessNotification.refreshReadiness))
}

@MainActor
@Test func disablingHelperDoesNotRefreshReadiness() {
    let posts = PostRecorder()
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .notRegistered },
        registrar: RecordingRegistrar(),
        preferenceStore: RecordingAutoRecordStore(),
        post: { posts.append($0) }
    )

    vm.toggle(enabled: false)

    #expect(posts.names.isEmpty)
}

private final class PostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Notification.Name] = []
    var names: [Notification.Name] { lock.withLock { stored } }
    func append(_ name: Notification.Name) { lock.withLock { stored.append(name) } }
}

@MainActor
@Test func disablingHelperUnregistersViaRegistrar() {
    let registrar = RecordingRegistrar()
    let preferences = RecordingAutoRecordStore()
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .notRegistered },
        registrar: registrar,
        preferenceStore: preferences
    )

    vm.toggle(enabled: false)

    #expect(registrar.registerCallCount == 0)
    #expect(registrar.unregisterCallCount == 1)
    #expect(preferences.savedValues == [false])
}

@MainActor
@Test func throwingRegistrarSurfacesErrorStatus() {
    let preferences = RecordingAutoRecordStore()
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .notRegistered },
        registrar: ThrowingRegistrar(),
        preferenceStore: preferences
    )

    vm.toggle(enabled: true)

    #expect(vm.statusLabel.contains("Error:"))
    #expect(preferences.savedValues.isEmpty)
}

private struct StubRegistrar: HelperRegistrar {
    func register() throws {}
    func unregister() throws {}
}

private final class RecordingAutoRecordStore: HelperAutoRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [Bool] = []

    var savedValues: [Bool] {
        lock.withLock { saved }
    }

    func isEnabled() -> Bool {
        savedValues.last ?? false
    }

    func save(enabled: Bool) {
        lock.withLock {
            saved.append(enabled)
        }
    }
}

private final class RecordingRegistrar: HelperRegistrar, @unchecked Sendable {
    private let lock = NSLock()
    private var registerCalls = 0
    private var unregisterCalls = 0

    var registerCallCount: Int {
        lock.withLock { registerCalls }
    }

    var unregisterCallCount: Int {
        lock.withLock { unregisterCalls }
    }

    func register() throws {
        lock.withLock {
            registerCalls += 1
        }
    }

    func unregister() throws {
        lock.withLock {
            unregisterCalls += 1
        }
    }
}

private struct ThrowingRegistrar: HelperRegistrar {
    func register() throws {
        throw TestError.registrationFailed
    }

    func unregister() throws {
        throw TestError.registrationFailed
    }
}

private enum TestError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "registration failed"
    }
}
#endif
