import Foundation
import Observation

@Observable
@MainActor
public final class ModelDownloadProgress {
    public enum State: String, Sendable, Equatable {
        case pending, active, paused, completed, failed, cancelled
    }

    public let manifestID: String
    public let totalBytes: Int64
    public private(set) var transferredBytes: Int64 = 0
    public private(set) var state: State = .pending
    public private(set) var bytesPerSecond: Double = 0
    public private(set) var etaSeconds: Double?
    public private(set) var errorReason: String?
    public private(set) var startedAt: Date?

    public init(manifestID: String, totalBytes: Int64) {
        self.manifestID = manifestID
        self.totalBytes = totalBytes
    }

    public var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100.0, Double(transferredBytes) / Double(totalBytes) * 100.0)
    }

    public func markStarted(at instant: Date) {
        state = .active
        startedAt = instant
    }

    /// Records a transferred-byte sample and recomputes throughput/ETA.
    ///
    /// No-ops once the download has reached a terminal state
    /// (`completed`/`failed`/`cancelled`) so late-draining async callbacks
    /// cannot overwrite finished values with a stale throughput/ETA flash.
    ///
    /// - Important: The caller MUST pass, for `startedAt`, the exact same
    ///   instant it passed to ``markStarted(at:)``. `startedAt` is
    ///   authoritative for the throughput/ETA math; `self.startedAt` tracks
    ///   state only and is not consulted here.
    public func transferred(bytes: Int64, at instant: Date, startedAt: Date) {
        guard state == .pending || state == .active || state == .paused else { return }
        if state == .pending { markStarted(at: startedAt) }
        transferredBytes = bytes
        let elapsed = instant.timeIntervalSince(startedAt)
        if elapsed > 0.5 {
            bytesPerSecond = Double(bytes) / elapsed
            let remaining = totalBytes - bytes
            etaSeconds = bytesPerSecond > 0 ? Double(remaining) / bytesPerSecond : nil
        }
    }

    public func markPaused() { state = .paused }

    public func markCancelled() { state = .cancelled }

    public func markCompleted() {
        state = .completed
        transferredBytes = totalBytes
        etaSeconds = 0
    }

    public func markFailed(reason: String) {
        state = .failed
        errorReason = reason
    }
}
