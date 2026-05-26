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
@Test func enablingHelperRegistersViaRegistrar() {
    let registrar = RecordingRegistrar()
    let preferences = RecordingAutoRecordStore()
    let vm = MeetingsHelperSettingsViewModel(
        statusProvider: { .enabled },
        registrar: registrar,
        preferenceStore: preferences
    )

    vm.toggle(enabled: true)

    #expect(registrar.registerCallCount == 1)
    #expect(registrar.unregisterCallCount == 0)
    #expect(preferences.savedValues == [true])
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
