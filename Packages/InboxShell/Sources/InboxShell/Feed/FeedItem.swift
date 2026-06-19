// Packages/InboxShell/Sources/InboxShell/Feed/FeedItem.swift
import Foundation

public enum FeedStream: String, CaseIterable, Sendable {
    case agent
    case meeting
    case bridge
}

public enum FeedRoute: Equatable, Sendable {
    case meeting(UUID)
    case dailyBrief
    case unscheduledTasks
    case agentInsight(UUID)
}

/// One projected feed row. `key` is the stable derived id (also `id`); the
/// state fields are joined from `FeedItemState` at projection time.
public struct FeedItem: Identifiable, Equatable, Sendable {
    public let key: String
    public let stream: FeedStream
    public let title: String
    public let subtitle: String?
    public let createdAt: Date
    public let route: FeedRoute
    public let iconName: String
    public var seenAt: Date?
    public var dismissedAt: Date?
    public var snoozedUntil: Date?

    public var id: String { key }

    public init(
        key: String, stream: FeedStream, title: String, subtitle: String?,
        createdAt: Date, route: FeedRoute, iconName: String,
        seenAt: Date? = nil, dismissedAt: Date? = nil, snoozedUntil: Date? = nil
    ) {
        self.key = key
        self.stream = stream
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.route = route
        self.iconName = iconName
        self.seenAt = seenAt
        self.dismissedAt = dismissedAt
        self.snoozedUntil = snoozedUntil
    }

    /// Hidden if dismissed, or snoozed into the future.
    public func isVisible(now: Date) -> Bool {
        if dismissedAt != nil { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        return true
    }

    /// Unread = visible and never seen. The bridge stream is never counted as
    /// unread (filtered by the registry, not here).
    public func isUnread(now: Date) -> Bool {
        isVisible(now: now) && seenAt == nil
    }
}
