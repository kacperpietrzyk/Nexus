import Foundation
import NexusCore
@preconcurrency import UserNotifications
import os

public struct AgentScheduleRunResult: Sendable {
    public let status: AgentScheduleStatus
    public let resultRef: UUID?
    public let error: String?

    public init(status: AgentScheduleStatus, resultRef: UUID?, error: String?) {
        self.status = status
        self.resultRef = resultRef
        self.error = error
    }
}

@MainActor
public final class AgentScheduleRunner {
    private let runtime: AgentRuntime
    private let threadStore: AgentThreadStore
    private let scheduleStore: AgentScheduleStore
    private let messageStore: AgentMessageStore
    private let notificationCenter: (any NotificationDelivering)?
    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.nexus.agent",
        category: "AgentScheduleRunner"
    )

    public init(
        runtime: AgentRuntime,
        threadStore: AgentThreadStore,
        scheduleStore: AgentScheduleStore,
        messageStore: AgentMessageStore? = nil,
        notificationCenter: (any NotificationDelivering)? = nil
    ) {
        self.runtime = runtime
        self.threadStore = threadStore
        self.scheduleStore = scheduleStore
        self.messageStore = messageStore ?? AgentMessageStore(context: scheduleStore.context)
        self.notificationCenter = notificationCenter
    }

    public func run(scheduleID: UUID, now: Date = .now) async throws -> AgentScheduleRunResult {
        try Task.checkCancellation()
        guard let schedule = try scheduleStore.get(id: scheduleID), schedule.enabled else {
            return AgentScheduleRunResult(status: .skipped, resultRef: nil, error: nil)
        }

        try Task.checkCancellation()
        let threadID = try threadID(for: schedule)
        try Task.checkCancellation()
        do {
            let response = try await runtime.runTurn(
                AgentTurnRequest(
                    threadID: threadID,
                    userMessage: schedule.prompt,
                    scope: "global",
                    providerHint: schedule.modelHint
                )
            )
            try Task.checkCancellation()
            let result = try record(response: response, schedule: schedule, threadID: threadID, now: now)
            if result.status == .success {
                await deliverBriefNotification(
                    response: response,
                    schedule: schedule,
                    resultRef: result.resultRef
                )
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let message = String(describing: error)
            logger.error("Scheduled agent run failed: \(message, privacy: .public)")
            try recordFailure(schedule: schedule, now: now)
            return AgentScheduleRunResult(status: .failed, resultRef: nil, error: message)
        }
    }

    private func threadID(for schedule: AgentSchedule) throws -> UUID {
        if let threadID = schedule.threadID {
            return threadID
        }

        let title = defaultThreadTitle(for: schedule.kind)
        let threadID: UUID
        if let existingID = try threadStore.allActive().first(where: { $0.title == title })?.id {
            threadID = existingID
        } else {
            threadID = try threadStore.create(
                title: title,
                projectID: schedule.projectID,
                modelHint: schedule.modelHint
            )
        }
        schedule.threadID = threadID
        return threadID
    }

    private func defaultThreadTitle(for kind: AgentScheduleKind) -> String {
        switch kind {
        case .builtIn:
            "Auto · Built-in schedules"
        case .projectDigest:
            "Auto · Project digest schedules"
        case .custom:
            "Auto · Custom schedules"
        }
    }

    private func record(
        response: AgentTurnResponse,
        schedule: AgentSchedule,
        threadID: UUID,
        now: Date
    ) throws -> AgentScheduleRunResult {
        switch response.haltReason {
        case .completed:
            guard let resultRef = try latestAssistantMessageID(threadID: threadID) else {
                throw AgentScheduleRunnerError.missingAssistantMessage
            }
            schedule.lastRunAt = now
            schedule.lastRunStatus = .success
            schedule.lastRunResultRef = resultRef
            try scheduleStore.touch(id: schedule.id, now: now)
            return AgentScheduleRunResult(status: .success, resultRef: resultRef, error: nil)
        case .maxIterationsReached:
            let error = "maxIterationsReached"
            try recordFailure(schedule: schedule, now: now)
            return AgentScheduleRunResult(status: .failed, resultRef: nil, error: error)
        case .providerError(let message):
            try recordFailure(schedule: schedule, now: now)
            return AgentScheduleRunResult(status: .failed, resultRef: nil, error: message)
        }
    }

    private func recordFailure(schedule: AgentSchedule, now: Date) throws {
        schedule.lastRunAt = now
        schedule.lastRunStatus = .failed
        schedule.lastRunResultRef = nil
        try scheduleStore.touch(id: schedule.id, now: now)
    }

    private func latestAssistantMessageID(threadID: UUID) throws -> UUID? {
        try messageStore
            .slidingWindow(threadID: threadID, last: 25)
            .reversed()
            .first { $0.role == .agent }?
            .id
    }

    private func deliverBriefNotification(
        response: AgentTurnResponse,
        schedule: AgentSchedule,
        resultRef: UUID?
    ) async {
        guard let notificationCenter,
            let body = Self.notificationBody(from: response.finalAssistantContent)
        else { return }

        do {
            try await notificationCenter.add(
                Self.notificationRequest(
                    schedule: schedule,
                    body: body,
                    resultRef: resultRef
                )
            )
        } catch {
            logger.error(
                "Scheduled agent notification failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private nonisolated static func notificationBody(from content: String?) -> String? {
        guard let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return String(trimmed.prefix(160))
    }

    private static func notificationRequest(
        schedule: AgentSchedule,
        body: String,
        resultRef: UUID?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = schedule.name
        content.body = body
        content.categoryIdentifier = "AGENT_BRIEF"
        content.threadIdentifier = "agent-schedule-\(schedule.id.uuidString)"
        var userInfo: [String: String] = [
            "type": "agent-schedule-brief",
            "scheduleID": schedule.id.uuidString,
        ]
        if let resultRef {
            userInfo["resultRef"] = resultRef.uuidString
        }
        content.userInfo = userInfo
        return UNNotificationRequest(
            identifier: "agent-schedule-\(schedule.id.uuidString)-\(resultRef?.uuidString ?? UUID().uuidString)",
            content: content,
            trigger: nil
        )
    }
}

private enum AgentScheduleRunnerError: Error, CustomStringConvertible {
    case missingAssistantMessage

    var description: String {
        switch self {
        case .missingAssistantMessage:
            "scheduled agent run completed without an assistant message"
        }
    }
}
