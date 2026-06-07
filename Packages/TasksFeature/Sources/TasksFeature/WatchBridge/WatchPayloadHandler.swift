import Foundation
import NexusCore
import OSLog
import SwiftData

/// Outcome of processing one inbound Watch payload.
public enum WatchPayloadOutcome: Sendable, Equatable {
    case inserted
    case updated
    case replied(String)
    case ignored
    case failed(String)
}

public typealias WatchAgentPromptHandling = @MainActor @Sendable (String) async throws -> String

/// Accept a proposed `ScheduledBlock` by id (spec §7 / §11). Injected by the
/// composition root, which owns the `CalendarSyncReconciler` (and thus EventKit);
/// the Watch relay never touches EventKit. Returns true when a block was accepted.
public typealias WatchBlockAcceptHandling = @MainActor @Sendable (UUID) async -> Bool

/// Pure entry point for Watch payloads. The platform-specific relay handles
/// WCSession and delegates parsing plus persistence here so unit tests can run
/// on the macOS host.
@MainActor
public final class WatchPayloadHandler {
    private let parser: any NLParser
    private let repository: TaskItemRepository
    private let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "WatchPayloadHandler")
    private let nowProvider: @Sendable () -> Date
    private let agentPromptHandler: WatchAgentPromptHandling?
    private let blockAcceptHandler: WatchBlockAcceptHandling?

    public init(
        parser: any NLParser,
        repository: TaskItemRepository,
        now: @escaping @Sendable () -> Date = { .now },
        agentPromptHandler: WatchAgentPromptHandling? = nil,
        blockAcceptHandler: WatchBlockAcceptHandling? = nil
    ) {
        self.parser = parser
        self.repository = repository
        self.nowProvider = now
        self.agentPromptHandler = agentPromptHandler
        self.blockAcceptHandler = blockAcceptHandler
    }

    public func handle(payload: [String: String]) async -> WatchPayloadOutcome {
        switch payload[WatchPayload.typeKey] {
        case WatchPayload.captureType:
            return await handleCapture(payload: payload)
        case WatchPayload.markDoneType:
            return handleAction(payload: payload) { [repository] task in
                try TaskCompletionAction.completeOrCascade(task, repository: repository)
            }
        case WatchPayload.reopenType:
            return handleAction(payload: payload, perform: repository.reopen)
        case WatchPayload.snoozeActionType:
            return handleSnoozeAction(payload: payload)
        case WatchPayload.askNexusType:
            return await handleAskNexus(payload: payload)
        case WatchPayload.acceptBlockType:
            return await handleAcceptBlock(payload: payload)
        default:
            return .ignored
        }
    }

    private func handleAcceptBlock(payload: [String: String]) async -> WatchPayloadOutcome {
        guard let handler = blockAcceptHandler else { return .ignored }
        guard
            let idString = payload[WatchPayload.blockIDKey],
            let blockID = UUID(uuidString: idString)
        else {
            return .ignored
        }
        return await handler(blockID) ? .updated : .ignored
    }

    private func handleCapture(payload: [String: String]) async -> WatchPayloadOutcome {
        guard
            let input = payload[WatchPayload.inputKey],
            !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .ignored
        }

        let parsed = await parser.parse(input, locale: .current, now: nowProvider())
        let task = TaskItem(
            title: parsed.title,
            dueAt: parsed.dueAt,
            startAt: parsed.startAt,
            endAt: parsed.endAt,
            deadlineAt: parsed.deadlineAt,
            priority: parsed.priority ?? .none,
            tags: parsed.tags,
            recurrenceRule: parsed.recurrence
        )

        do {
            try repository.insert(task)
            return .inserted
        } catch {
            logger.error("Watch capture insert failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private func handleAction(
        payload: [String: String],
        perform: (TaskItem) throws -> Void
    ) -> WatchPayloadOutcome {
        guard
            let idString = payload[WatchPayload.taskIDKey],
            let taskID = UUID(uuidString: idString)
        else {
            return .ignored
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil }
        )
        guard let task = (try? repository.context.fetch(descriptor))?.first else {
            return .ignored
        }

        do {
            try perform(task)
            return .updated
        } catch {
            logger.error("Watch action failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private func handleSnoozeAction(payload: [String: String]) -> WatchPayloadOutcome {
        guard
            let idString = payload[WatchPayload.taskIDKey],
            let taskID = UUID(uuidString: idString),
            let untilString = payload[WatchPayload.snoozeUntilKey],
            let until = ISO8601DateFormatter().date(from: untilString)
        else {
            return .ignored
        }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil }
        )
        guard let task = (try? repository.context.fetch(descriptor))?.first else {
            return .ignored
        }
        do {
            try repository.snooze(task, until: until)
            return .updated
        } catch {
            logger.error("Watch snooze action failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private func handleAskNexus(payload: [String: String]) async -> WatchPayloadOutcome {
        guard let agentPromptHandler else {
            return .ignored
        }
        guard
            let prompt = payload[WatchPayload.promptKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !prompt.isEmpty
        else {
            return .ignored
        }
        do {
            let reply = try await agentPromptHandler(prompt)
            return .replied(reply)
        } catch {
            logger.error("Watch Ask Nexus failed: \(String(describing: error), privacy: .public)")
            return .failed(String(describing: error))
        }
    }
}
