import Foundation
import Testing

@testable import NexusMeetings

#if os(macOS)
@preconcurrency import ServiceManagement

@MainActor
@Test func welcomeStepSkipPersistsDisabledAndContinuesFalse() {
    let preferences = RecordingAutoRecordStore()
    let viewModel = MeetingsWelcomeStepViewModel(
        registrar: RecordingRegistrar(),
        statusProvider: { .notRegistered },
        preferenceStore: preferences
    )
    var continuedChoice: Bool?

    viewModel.skip { enabled in
        continuedChoice = enabled
    }

    #expect(preferences.savedValues == [false])
    #expect(continuedChoice == false)
}

@MainActor
@Test func welcomeStepContinueOffPersistsDisabledWithoutRegistering() {
    let registrar = RecordingRegistrar()
    let preferences = RecordingAutoRecordStore()
    let viewModel = MeetingsWelcomeStepViewModel(
        enableHelper: false,
        registrar: registrar,
        statusProvider: { .notRegistered },
        preferenceStore: preferences
    )
    var continuedChoice: Bool?

    viewModel.continueFlow { enabled in
        continuedChoice = enabled
    }

    #expect(registrar.registerCallCount == 0)
    #expect(preferences.savedValues == [false])
    #expect(continuedChoice == false)
}

@MainActor
@Test func welcomeStepContinueEnabledRegistersPersistsAndRequestsMicInProcess() {
    let registrar = RecordingRegistrar()
    let preferences = RecordingAutoRecordStore()
    let micFlag = MicRequestFlag()
    let viewModel = MeetingsWelcomeStepViewModel(
        registrar: registrar,
        statusProvider: { .notRegistered },
        preferenceStore: preferences,
        requestMicrophoneAccess: { completion in
            micFlag.markCalled()
            completion(true)
        }
    )
    var continuedChoice: Bool?

    viewModel.continueFlow { enabled in
        continuedChoice = enabled
    }

    #expect(registrar.registerCallCount == 1)
    #expect(preferences.savedValues == [true])
    #expect(continuedChoice == true)
    // Microphone is requested IN-PROCESS by the main app (no sandboxed helper).
    #expect(micFlag.wasCalled)
}

private final class MicRequestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    var wasCalled: Bool { lock.withLock { called } }
    func markCalled() { lock.withLock { called = true } }
}

@MainActor
@Test func welcomeStepRegistrationFailureKeepsStepOpen() {
    let preferences = RecordingAutoRecordStore()
    let viewModel = MeetingsWelcomeStepViewModel(
        registrar: ThrowingRegistrar(),
        statusProvider: { .notRegistered },
        preferenceStore: preferences
    )
    var didContinue = false

    viewModel.continueFlow { _ in
        didContinue = true
    }

    #expect(didContinue == false)
    #expect(preferences.savedValues.isEmpty)
    #expect(viewModel.statusText?.contains("registration failed") == true)
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

    var registerCallCount: Int {
        lock.withLock { registerCalls }
    }

    func register() throws {
        lock.withLock {
            registerCalls += 1
        }
    }

    func unregister() throws {}
}

private struct ThrowingRegistrar: HelperRegistrar {
    func register() throws {
        throw TestError.registrationFailed
    }

    func unregister() throws {}
}

private enum TestError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "registration failed"
    }
}
#endif
