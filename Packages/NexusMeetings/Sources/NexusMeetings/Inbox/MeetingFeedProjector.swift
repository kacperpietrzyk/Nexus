// Packages/NexusMeetings/Sources/NexusMeetings/Inbox/MeetingFeedProjector.swift
import Foundation
import InboxShell
import NexusCore
import SwiftData

/// Builds `[MeetingFeedProjector.Snapshot]` from the meeting + link stores, the
/// composition-root glue behind `MeetingFeedProjector`. The queries are lifted
/// from the deleted `MeetingActionItemsInboxSource`: all non-deleted meetings in
/// chronological order, joined to a single batched outgoing-link fetch
/// (`.actionItem` → `.task`) for the action-item count. `@MainActor` to match the
/// SwiftData isolation used across the repositories.
@MainActor
public struct MeetingFeedSnapshotBuilder {
    private let meetingRepository: MeetingRepository
    private let linkRepository: LinkRepository

    public init(context: ModelContext) {
        self.meetingRepository = MeetingRepository(context: context)
        self.linkRepository = LinkRepository(context: context)
    }

    public func snapshots() throws -> [MeetingFeedProjector.Snapshot] {
        let meetings = try meetingRepository.allChronological().filter { $0.deletedAt == nil }
        guard !meetings.isEmpty else { return [] }
        // Single batched outgoing-link fetch for ALL meetings (no per-meeting
        // N+1), filtered to action-item → task edges for the count.
        let linksByMeetingID = try linkRepository.outgoing(
            fromKind: .meeting,
            fromIDs: meetings.map(\.id)
        )
        return meetings.map { meeting in
            let actionItemCount = (linksByMeetingID[meeting.id] ?? []).reduce(into: 0) { count, link in
                if link.linkKind == .actionItem, link.toKind == .task { count += 1 }
            }
            return MeetingFeedProjector.Snapshot(
                id: meeting.id,
                title: meeting.title,
                hasSummary: !meeting.summaryText.isEmpty,
                actionItemCount: actionItemCount,
                eventDate: meeting.processedAt ?? meeting.updatedAt
            )
        }
    }
}

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
