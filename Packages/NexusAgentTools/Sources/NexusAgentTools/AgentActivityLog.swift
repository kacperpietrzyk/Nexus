import Foundation
import Observation

/// In-memory ring buffer of recent agent tool calls.
///
/// The log is UI-observable, main-actor-bound, and intentionally ephemeral in
/// Phase 1h; it resets when the app exits.
@MainActor
@Observable
public final class AgentActivityLog {
    public static let maxEntries = 200

    public private(set) var entries: [AgentActivityEntry] = []

    public init() {}

    public func record(_ entry: AgentActivityEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}

public struct AgentActivityEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let toolName: String
    public let argsRedacted: String
    public let resultStatus: ResultStatus
    public let durationMs: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        toolName: String,
        argsRedacted: String,
        resultStatus: ResultStatus,
        durationMs: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.toolName = toolName
        self.argsRedacted = argsRedacted
        self.resultStatus = resultStatus
        self.durationMs = durationMs
    }

    public static func success(name: String, argsRedacted: String, durationMs: Int) -> AgentActivityEntry {
        AgentActivityEntry(
            toolName: name,
            argsRedacted: argsRedacted,
            resultStatus: .ok,
            durationMs: durationMs
        )
    }

    public static func failure(
        name: String,
        argsRedacted: String,
        code: Int,
        durationMs: Int
    ) -> AgentActivityEntry {
        AgentActivityEntry(
            toolName: name,
            argsRedacted: argsRedacted,
            resultStatus: .errorCode(code),
            durationMs: durationMs
        )
    }
}

public enum ResultStatus: Sendable, Equatable {
    case ok
    case errorCode(Int)
}
