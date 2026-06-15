import Foundation

/// Wire-format meeting projection shipped from iPhone to Watch in reply to a
/// `meetings-recent-query` (spec: Watch is a glance device, NexusMeetings has no
/// watchOS platform so the `Meeting` type itself cannot cross the boundary).
///
/// A standalone, `Meeting`-free struct: NexusCore cannot import NexusMeetings,
/// so the iPhone composition root maps `Meeting → WatchMeetingGlance` and the
/// Watch caches the decoded array. Carries only the minimum the glance needs.
public struct WatchMeetingGlance: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    /// Truncated summary text (the iPhone caps this so the JSON stays under the
    /// WatchConnectivity reply size ceiling).
    public let summarySnippet: String
    public let actionItemCount: Int
    public let startedAt: Date

    public init(
        id: UUID,
        title: String,
        summarySnippet: String,
        actionItemCount: Int,
        startedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summarySnippet = summarySnippet
        self.actionItemCount = actionItemCount
        self.startedAt = startedAt
    }
}

/// JSON envelope for an array of glances. A dedicated wrapper keeps the wire
/// payload self-describing (mirrors `NotificationSnapshot`'s `generatedAt`).
public struct WatchMeetingGlanceSnapshot: Codable, Sendable, Equatable {
    public let meetings: [WatchMeetingGlance]
    public let generatedAt: Date

    public init(meetings: [WatchMeetingGlance], generatedAt: Date) {
        self.meetings = meetings
        self.generatedAt = generatedAt
    }
}
