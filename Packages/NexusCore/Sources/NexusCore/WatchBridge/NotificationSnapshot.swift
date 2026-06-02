import Foundation

/// Wire-format payload pushed from iPhone to Watch on every repository write
/// that affects a notification. Watch caches the most recent snapshot in an
/// App Group file and uses it to install local notification triggers when
/// the iPhone is unreachable. Carries only the minimum the Watch needs to
/// render the rich notification UI and re-arm itself.
public struct NotificationSnapshot: Codable, Sendable, Equatable {
    public let entries: [NotificationSnapshotEntry]
    public let generatedAt: Date
    public let horizon: TimeInterval

    public init(entries: [NotificationSnapshotEntry], generatedAt: Date, horizon: TimeInterval) {
        self.entries = entries
        self.generatedAt = generatedAt
        self.horizon = horizon
    }
}

public struct NotificationSnapshotEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let dueAt: Date?
    public let projectName: String?
    public let snoozedUntil: Date?

    public init(
        id: UUID,
        title: String,
        dueAt: Date?,
        projectName: String?,
        snoozedUntil: Date?
    ) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.projectName = projectName
        self.snoozedUntil = snoozedUntil
    }

    /// Effective trigger time used by the Watch scheduler. For snoozed tasks
    /// this is the snooze release time; for everything else it's the due time.
    /// A snoozed entry without a due date still has a trigger via `snoozedUntil`;
    /// the encoder guarantees at least one of the two is non-nil.
    public var effectiveTriggerAt: Date {
        snoozedUntil ?? dueAt ?? .distantPast
    }
}
