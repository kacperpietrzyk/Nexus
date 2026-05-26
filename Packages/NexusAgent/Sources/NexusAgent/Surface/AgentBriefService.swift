import Foundation
import SwiftUI

public struct AgentBriefCounts: Sendable, Hashable {
    public let overdue: Int
    public let today: Int
    public let noDate: Int
    public let awaiting: Int

    public init(overdue: Int, today: Int, noDate: Int, awaiting: Int) {
        self.overdue = overdue
        self.today = today
        self.noDate = noDate
        self.awaiting = awaiting
    }
}

public struct AgentBriefRequest: Sendable, Equatable {
    public let counts: AgentBriefCounts
    public let firstTitles: [String]
    public let now: Date

    public init(counts: AgentBriefCounts, firstTitles: [String], now: Date) {
        self.counts = counts
        self.firstTitles = firstTitles
        self.now = now
    }
}

@MainActor
public protocol AgentBriefServiceProtocol: Sendable {
    func brief(for request: AgentBriefRequest) async -> String
}

@MainActor
public final class AgentBriefService: AgentBriefServiceProtocol, @unchecked Sendable {
    private struct CacheKey: Hashable {
        let dayBucket: Date
        let counts: AgentBriefCounts
        let firstTitles: [String]
    }

    private struct CacheEntry {
        let value: String
        let timestamp: Date
    }

    private let runtime: AgentRuntime?
    private let threadStore: AgentThreadStore?
    private let pinnedThreadTitle: String
    private let legacy: @Sendable (AgentBriefRequest) async -> String
    private let isEnabled: @Sendable () -> Bool
    private let calendar: Calendar
    private let ttl: TimeInterval
    private var cache: [CacheKey: CacheEntry] = [:]
    private var inFlight: [CacheKey: Task<String, Never>] = [:]

    public init(
        runtime: AgentRuntime?,
        threadStore: AgentThreadStore?,
        pinnedThreadTitle: String = "Daily Briefs",
        legacy: @escaping @Sendable (AgentBriefRequest) async -> String,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        calendar: Calendar = .current,
        ttl: TimeInterval = 30 * 60
    ) {
        self.runtime = runtime
        self.threadStore = threadStore
        self.pinnedThreadTitle = pinnedThreadTitle
        self.legacy = legacy
        self.isEnabled = isEnabled
        self.calendar = calendar
        self.ttl = ttl
    }

    public func brief(for request: AgentBriefRequest) async -> String {
        guard isEnabled(), let runtime, let threadStore else {
            return await legacy(request)
        }

        let key = cacheKey(for: request)
        let now = Date.now
        if let entry = cache[key], now.timeIntervalSince(entry.timestamp) < ttl {
            return entry.value
        }
        cache[key] = nil

        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task { @MainActor [self] in
            let text = await resolveBrief(for: request, runtime: runtime, threadStore: threadStore)
            cache[key] = CacheEntry(value: text, timestamp: Date.now)
            inFlight[key] = nil
            return text
        }
        inFlight[key] = task
        return await task.value
    }

    private func resolveBrief(
        for request: AgentBriefRequest,
        runtime: AgentRuntime,
        threadStore: AgentThreadStore
    ) async -> String {
        do {
            let threadID = try pinnedThreadID(in: threadStore)
            let response = try await runtime.runTurn(
                AgentTurnRequest(
                    threadID: threadID,
                    userMessage: Self.prompt(for: request),
                    scope: "global"
                )
            )
            guard response.haltReason == .completed else {
                return await legacy(request)
            }

            let content =
                response.finalAssistantContent?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return content.isEmpty ? await legacy(request) : content
        } catch {
            return await legacy(request)
        }
    }

    private func cacheKey(for request: AgentBriefRequest) -> CacheKey {
        CacheKey(
            dayBucket: calendar.startOfDay(for: request.now),
            counts: request.counts,
            firstTitles: Array(request.firstTitles.prefix(3))
        )
    }

    private func pinnedThreadID(in threadStore: AgentThreadStore) throws -> UUID {
        if let existing = try threadStore.allActive().first(where: { $0.title == pinnedThreadTitle }) {
            return existing.id
        }
        return try threadStore.create(title: pinnedThreadTitle)
    }

    private static func prompt(for request: AgentBriefRequest) -> String {
        let counts = request.counts
        let titles = request.firstTitles.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let formattedDate = Self.dateFormatter.string(from: request.now)
        return """
            Write today's brief for the Today view in Nexus.
            Keep the tone concrete, calm, and operational. Return only the finished brief.
            Format: 1-2 short paragraphs. Use at most two [[accent]]...[[/accent]] markers.

            Date: \(formattedDate)
            Numbers: \(counts.overdue) overdue, \(counts.today) today, \
            \(counts.noDate) with no date, \(counts.awaiting) blocking.
            First tasks:
            \(titles.isEmpty ? "- none" : titles)
            """
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // English UI — explicit en_US (system locale may be pl_PL)
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct AgentBriefServiceKey: EnvironmentKey {
    static let defaultValue: (any AgentBriefServiceProtocol)? = nil
}

extension EnvironmentValues {
    public var agentBriefService: (any AgentBriefServiceProtocol)? {
        get { self[AgentBriefServiceKey.self] }
        set { self[AgentBriefServiceKey.self] = newValue }
    }
}
