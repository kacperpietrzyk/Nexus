import Foundation

public enum SyncPhase: String, Sendable, CaseIterable {
    case idle
    case syncing
    case synced
    case failed
}

/// UI signal for the sync subsystem. Apps observe this via `@Bindable`.
@MainActor
@Observable
public final class SyncState {
    public private(set) var phase: SyncPhase = .idle
    public private(set) var lastSyncedAt: Date?
    public private(set) var lastError: (any Error)?

    public init() {}

    public func began() {
        phase = .syncing
        lastError = nil
    }

    public func succeeded(at date: Date) {
        phase = .synced
        lastSyncedAt = date
        lastError = nil
    }

    public func failed(_ error: any Error) {
        phase = .failed
        lastError = error
    }

    public func reset() {
        phase = .idle
        lastError = nil
    }
}
