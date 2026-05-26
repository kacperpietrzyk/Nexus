import Foundation
import NexusCore

/// TasksFeature-side typed protocol layered on top of the `WatchSnapshotPusher`
/// closure. Composition wires a concrete `WCSessionWatchSnapshotPusher` on
/// iPhone and `NoopWatchSnapshotPusher` everywhere else.
@MainActor
public protocol WatchSnapshotPushing: Sendable {
    func push(_ snapshot: NotificationSnapshot) async
}

public struct NoopWatchSnapshotPusher: WatchSnapshotPushing {
    public init() {}
    public func push(_: NotificationSnapshot) async {}
}

#if os(iOS)
import WatchConnectivity

/// iPhone-side production pusher. Encodes the snapshot to JSON and ships it
/// via `WCSession.transferUserInfo`. Falls back gracefully when no Watch is
/// paired or installed — there's no point bouncing snapshots off thin air.
public final class WCSessionWatchSnapshotPusher: WatchSnapshotPushing {
    public init() {}

    public func push(_ snapshot: NotificationSnapshot) async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot),
            let json = String(data: data, encoding: .utf8)
        else { return }
        session.transferUserInfo([
            WatchPayload.typeKey: WatchPayload.notifSnapshotType,
            WatchPayload.snapshotPayloadKey: json,
        ])
    }
}
#endif
