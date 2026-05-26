import Foundation
import NexusCore
import Testing

@testable import NexusWatch

@Suite("WatchNotificationSnapshotStore")
struct WatchNotificationSnapshotStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-watch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func roundtrip_save_then_load() throws {
        let dir = try makeTempDir()
        let store = WatchNotificationSnapshotStore(directory: dir)
        let snapshot = NotificationSnapshot(
            entries: [
                NotificationSnapshotEntry(
                    id: UUID(),
                    title: "x",
                    dueAt: Date(),
                    projectName: nil,
                    snoozedUntil: nil
                )
            ],
            generatedAt: Date(),
            horizon: 86_400
        )
        try store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test func corrupted_json_returns_nil() throws {
        let dir = try makeTempDir()
        let store = WatchNotificationSnapshotStore(directory: dir)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("notif-snapshot.json"))
        #expect(store.load() == nil)
    }

    @Test func empty_directory_returns_nil() throws {
        let dir = try makeTempDir()
        let store = WatchNotificationSnapshotStore(directory: dir)
        #expect(store.load() == nil)
    }
}
