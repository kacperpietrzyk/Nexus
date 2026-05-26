import Foundation
import SwiftData
import os

public struct AgentMessagePruneSummary: Equatable, Sendable {
    public let redacted: Int
    public let preserved: Int
}

public enum AgentMessagePrunerOutcome: Sendable, Equatable {
    case ran(AgentMessagePruneSummary)
    case skipped
}

public struct AgentMessagePruner: Sendable {
    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.nexus.agent",
        category: "AgentMessagePruner"
    )

    public init() {}

    public func runIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = .now,
        cadence: TimeInterval = 86_400,
        retainDays: Int = 30
    ) throws -> AgentMessagePrunerOutcome {
        let key = "AgentMessagePruner.lastRunAt"
        if let last = defaults.object(forKey: key) as? Date, now.timeIntervalSince(last) < cadence {
            return .skipped
        }
        let summary = try prune(context: context, now: now, retainDays: retainDays)
        defaults.set(now, forKey: key)
        return .ran(summary)
    }

    public func prune(
        context: ModelContext,
        now: Date = .now,
        retainDays: Int = 30
    ) throws -> AgentMessagePruneSummary {
        let cutoff = now.addingTimeInterval(-Double(retainDays) * 86_400)
        let stale = try context.fetch(
            FetchDescriptor<AgentMessage>(
                predicate: #Predicate { $0.createdAt < cutoff && !$0.redactedContent }
            )
        )
        for msg in stale {
            msg.content = redact(msg.content)
            msg.redactedContent = true
        }
        let preserved = try context.fetchCount(
            FetchDescriptor<AgentMessage>(
                predicate: #Predicate { $0.createdAt >= cutoff }
            )
        )
        try context.save()
        logger.info("pruned \(stale.count) messages, kept \(preserved) full")
        return AgentMessagePruneSummary(redacted: stale.count, preserved: preserved)
    }

    private func redact(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let summary = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return String(summary.prefix(160))
    }
}
