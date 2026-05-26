import Foundation
import NexusCore
import OSLog

/// Persists the most recent `NotificationSnapshot` pushed from the iPhone.
/// Lives in the App Group container so that the Watch app, complications,
/// and any future Watch extensions all observe the same payload.
final class WatchNotificationSnapshotStore: Sendable {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus",
        category: "WatchNotifSnapshot"
    )
    private static let fileName = "notif-snapshot.json"

    private let fileURL: URL

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }

    convenience init?() {
        let dir: URL
        if let groupDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.kacperpietrzyk.Nexus"
        ) {
            dir = groupDir
        } else {
            do {
                dir = try Self.localFallbackDirectory()
                Self.logger.warning("App Group unavailable; using Watch-local notification snapshot store")
            } catch {
                Self.logger.error(
                    "Failed to create Watch-local notification snapshot store: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        self.init(directory: dir)
    }

    private static func localFallbackDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Nexus/Watch", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func save(_ snapshot: NotificationSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func load() -> NotificationSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(NotificationSnapshot.self, from: data)
        } catch {
            Self.logger.error(
                "Snapshot decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
