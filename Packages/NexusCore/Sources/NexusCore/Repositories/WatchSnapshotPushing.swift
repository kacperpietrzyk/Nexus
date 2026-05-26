import Foundation

/// Sendable post-write hook the repository calls after every mutation that
/// could affect notifications. TasksFeature wires the production
/// `WCSession`-backed pusher; Mac and tests wire a no-op closure.
///
/// The closure receives no arguments — it's a "tickle me" signal. The
/// concrete pusher (in TasksFeature) re-encodes the snapshot from its own
/// `ModelContext` reference. Keeps NexusCore free of TasksFeature types.
public typealias WatchSnapshotPusher = @MainActor @Sendable () async -> Void

public let noopWatchSnapshotPusher: WatchSnapshotPusher = {}
