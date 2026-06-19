// Packages/NexusAgent/Sources/NexusAgent/Inbox/DailyBriefProjector.swift
import Foundation
import InboxShell
import NexusCore

/// Emits today's daily-brief note as one Agent-stream feed row. The day key and
/// note snapshot are injected; the composition root supplies the real providers
/// (see `AgentBriefDailyNoteWriter.todayDailyNote` + `DailyNoteConvention`).
public struct DailyBriefProjector: FeedProjector {
    public let stream: FeedStream = .agent
    private let dayKeyProvider: @Sendable () -> String
    private let snapshotProvider: @Sendable () async throws -> (text: String, updatedAt: Date)?

    public init(
        dayKeyProvider: @escaping @Sendable () -> String,
        snapshotProvider: @escaping @Sendable () async throws -> (text: String, updatedAt: Date)?
    ) {
        self.dayKeyProvider = dayKeyProvider
        self.snapshotProvider = snapshotProvider
    }

    /// The stable feed key for the daily brief on the day containing `date`:
    /// `"brief:" + yyyy-MM-dd` (the prefix the `FeedItemState` doc convention
    /// cites). Shares `DailyNoteConvention.dayKey` so the key tracks the same
    /// per-day identity the canonical daily note uses.
    public static func dayKey(for date: Date) -> String {
        "brief:" + DailyNoteConvention.dayKey(for: date)
    }

    public func project() async throws -> [FeedItem] {
        guard let snapshot = try await snapshotProvider() else { return [] }
        let firstLine = snapshot.text
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        let subtitle = firstLine.map { String($0.prefix(120)) }
        return [
            FeedItem(
                key: dayKeyProvider(),
                stream: .agent,
                title: "Daily brief",
                subtitle: subtitle,
                createdAt: snapshot.updatedAt,
                route: .dailyBrief,
                iconName: "sparkles"
            )
        ]
    }
}
