import Foundation
import NexusCore
import OSLog

/// Persists the most recent `WatchMeetingGlanceSnapshot` replied from the iPhone
/// so the Watch meetings glance reads local data without blocking on
/// connectivity. Lives in the App Group container (mirrors
/// `WatchNotificationSnapshotStore`) so any future Watch surfaces share it.
final class WatchMeetingGlanceStore: Sendable {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus",
        category: "WatchMeetingGlance"
    )
    private static let fileName = "meeting-glances.json"

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
                Self.logger.warning("App Group unavailable; using Watch-local meeting glance store")
            } catch {
                Self.logger.error(
                    "Failed to create Watch-local meeting glance store: \(error.localizedDescription, privacy: .public)"
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

    func save(_ snapshot: WatchMeetingGlanceSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func load() -> WatchMeetingGlanceSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(WatchMeetingGlanceSnapshot.self, from: data)
        } catch {
            Self.logger.error(
                "Meeting glance decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
