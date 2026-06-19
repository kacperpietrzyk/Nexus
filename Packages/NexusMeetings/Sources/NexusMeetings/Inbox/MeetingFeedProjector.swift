// Packages/NexusMeetings/Sources/NexusMeetings/Inbox/MeetingFeedProjector.swift
import Foundation
import InboxShell

/// One feed row per meeting that produced something to review (a summary and/or
/// extracted action items). The data snapshot is injected so the projector is
/// testable; the composition root supplies the real provider reading the meeting
/// + link repositories (see `MeetingActionItemsInboxSource` for the queries).
public struct MeetingFeedProjector: FeedProjector {
    public struct Snapshot: Sendable {
        public let id: UUID
        public let title: String
        public let hasSummary: Bool
        public let actionItemCount: Int
        public let eventDate: Date
        public init(id: UUID, title: String, hasSummary: Bool, actionItemCount: Int, eventDate: Date) {
            self.id = id
            self.title = title
            self.hasSummary = hasSummary
            self.actionItemCount = actionItemCount
            self.eventDate = eventDate
        }
    }

    public let stream: FeedStream = .meeting
    private let snapshotProvider: @Sendable () async throws -> [Snapshot]

    public init(snapshotProvider: @escaping @Sendable () async throws -> [Snapshot]) {
        self.snapshotProvider = snapshotProvider
    }

    public func project() async throws -> [FeedItem] {
        try await snapshotProvider().compactMap { meeting in
            guard meeting.hasSummary || meeting.actionItemCount > 0 else { return nil }
            return FeedItem(
                key: "meeting:\(meeting.id.uuidString)",
                stream: .meeting,
                title: meeting.title,
                subtitle: Self.subtitle(hasSummary: meeting.hasSummary, actionItems: meeting.actionItemCount),
                createdAt: meeting.eventDate,
                route: .meeting(meeting.id),
                iconName: "person.2"
            )
        }
    }

    static func subtitle(hasSummary: Bool, actionItems: Int) -> String? {
        var parts: [String] = []
        if hasSummary { parts.append("Summary ready") }
        if actionItems > 0 { parts.append("\(actionItems) action item\(actionItems == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
