// Packages/NexusAgent/Sources/NexusAgent/Inbox/AgentInsightProjector.swift
import Foundation
import InboxShell

/// Projects open (unresolved) persisted agent insights into the Agent stream.
/// The records are injected so the projector is testable; the composition root
/// supplies the real provider reading `AgentInsightRepository.open()`.
public struct AgentInsightProjector: FeedProjector {
    public struct Row: Sendable {
        public let id: UUID
        public let title: String
        public let kind: String
        public let createdAt: Date
        public init(id: UUID, title: String, kind: String, createdAt: Date) {
            self.id = id
            self.title = title
            self.kind = kind
            self.createdAt = createdAt
        }
    }

    public let stream: FeedStream = .agent
    private let openProvider: @Sendable () async throws -> [Row]

    public init(openProvider: @escaping @Sendable () async throws -> [Row]) {
        self.openProvider = openProvider
    }

    public func project() async throws -> [FeedItem] {
        try await openProvider().map { row in
            FeedItem(
                key: "insight:\(row.id.uuidString)",
                stream: .agent,
                title: row.title,
                subtitle: Self.humanize(row.kind),
                createdAt: row.createdAt,
                route: .agentInsight(row.id),
                iconName: "sparkles"
            )
        }
    }

    static func humanize(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
