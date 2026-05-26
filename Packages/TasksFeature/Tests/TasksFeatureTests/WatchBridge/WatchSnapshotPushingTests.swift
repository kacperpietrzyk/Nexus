import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("WatchSnapshotPushing")
@MainActor
struct WatchSnapshotPushingTests {
    @Test func noop_pusher_does_nothing_and_does_not_throw() async {
        let pusher = NoopWatchSnapshotPusher()
        let snapshot = NotificationSnapshot(entries: [], generatedAt: .now, horizon: 86_400)
        await pusher.push(snapshot)
        // No assertion needed — `Noop` is a no-op; reaching here without crash is the test.
    }
}
