import Foundation
import Testing

@testable import NexusSync

@MainActor
@Test func syncState_initial_isIdle() {
    let state = SyncState()
    #expect(state.phase == .idle)
    #expect(state.lastError == nil)
}

@MainActor
@Test func syncState_transitions_areObservable() {
    let state = SyncState()
    state.began()
    #expect(state.phase == .syncing)

    state.succeeded(at: .now)
    #expect(state.phase == .synced)
    #expect(state.lastSyncedAt != nil)
}

@MainActor
@Test func syncState_failure_storesError() {
    let state = SyncState()
    state.failed(SyncStateError.test)
    #expect(state.phase == .failed)
    #expect(state.lastError as? SyncStateError == .test)
}

@MainActor
@Test func syncState_reset_returnsToIdleAndClearsError() {
    let state = SyncState()
    state.failed(SyncStateError.test)
    #expect(state.phase == .failed)
    #expect(state.lastError != nil)

    state.reset()
    #expect(state.phase == .idle)
    #expect(state.lastError == nil)
}

private enum SyncStateError: Error, Equatable {
    case test
}
