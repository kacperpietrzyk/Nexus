// Packages/NexusAgent/Sources/NexusAgent/Inbox/DailyBriefProjector.swift
import Foundation
import InboxShell

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
