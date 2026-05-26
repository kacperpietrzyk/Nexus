import Foundation
import NexusCore
import OSLog
@preconcurrency import UserNotifications

public struct WatchAgentReply: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum WatchAgentHandlerError: Error, Equatable {
    case emptyPrompt
    case maxIterationsReached
    case providerError(String)
}

@MainActor
public final class WatchAgentHandler {
    public nonisolated static let threadTitle = "Watch · Ask Nexus"
    public nonisolated static let notificationCategoryIdentifier = NotificationCategory.watchAgentReply.rawValue
    public nonisolated static let notificationThreadIdentifier = "watch-agent"

    private let runtime: AgentRuntime
    private let threadStore: AgentThreadStore
    private let notificationCenter: any NotificationDelivering
    private let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "WatchAgentHandler")

    public init(
        runtime: AgentRuntime,
        threadStore: AgentThreadStore,
        notificationCenter: any NotificationDelivering
    ) {
        self.runtime = runtime
        self.threadStore = threadStore
        self.notificationCenter = notificationCenter
    }

    public func handle(prompt: String) async throws -> WatchAgentReply {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw WatchAgentHandlerError.emptyPrompt
        }

        let threadID = try resolveWatchThread()
        let response = try await runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: trimmedPrompt,
                scope: "global"
            )
        )
        guard response.haltReason == .completed else {
            throw Self.error(for: response.haltReason)
        }

        let replyText = Self.replyText(from: response.finalAssistantContent)
        do {
            try await notificationCenter.add(
                Self.notificationRequest(text: replyText, threadID: threadID)
            )
        } catch {
            logger.error("Watch agent reply notification failed: \(error.localizedDescription, privacy: .public)")
        }
        return WatchAgentReply(text: replyText)
    }

    private func resolveWatchThread() throws -> UUID {
        let existingID = try threadStore.allActive().first { $0.title == Self.threadTitle }?.id
        if let existingID {
            return existingID
        }
        return try threadStore.create(title: Self.threadTitle)
    }

    private nonisolated static func replyText(from content: String?) -> String {
        let normalized = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if let normalized, !normalized.isEmpty {
            text = normalized
        } else {
            text = "Brak odpowiedzi."
        }
        return String(text.prefix(160))
    }

    private nonisolated static func error(for haltReason: AgentTurnHaltReason) -> WatchAgentHandlerError {
        switch haltReason {
        case .completed:
            preconditionFailure("Completed Watch agent turns are handled as success.")
        case .maxIterationsReached:
            return .maxIterationsReached
        case .providerError(let message):
            return .providerError(message)
        }
    }

    private nonisolated static func notificationRequest(text: String, threadID: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Nexus"
        content.body = text
        content.categoryIdentifier = notificationCategoryIdentifier
        content.threadIdentifier = notificationThreadIdentifier
        content.userInfo = [
            "type": "watch-agent-reply",
            "threadID": threadID.uuidString,
        ]
        return UNNotificationRequest(
            identifier: "watch-agent-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
    }
}

extension WatchAgentHandlerError: CustomStringConvertible, LocalizedError {
    public var description: String {
        switch self {
        case .emptyPrompt:
            return "Prompt is empty."
        case .maxIterationsReached:
            return "Agent reached the maximum number of iterations."
        case .providerError(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}
