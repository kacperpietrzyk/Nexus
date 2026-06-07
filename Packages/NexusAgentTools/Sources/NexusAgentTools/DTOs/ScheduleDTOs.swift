import Foundation
import NexusCore

/// Wire format for a `DurationEstimate` (spec §12 `tasks.estimateDuration`).
/// snake_case keys per MCP convention. Read-only — the estimate is computed, not
/// persisted, by `tasks.estimateDuration`.
public struct DurationEstimateDTO: Codable, Sendable, Equatable {
    public let taskID: String
    public let seconds: Int
    public let confidence: Double

    private enum CodingKeys: String, CodingKey {
        case seconds, confidence
        case taskID = "task_id"
    }

    public init(taskID: String, seconds: Int, confidence: Double) {
        self.taskID = taskID
        self.seconds = seconds
        self.confidence = confidence
    }

    public init(taskID: UUID, estimate: DurationEstimate) {
        self.taskID = taskID.uuidString
        self.seconds = estimate.seconds
        self.confidence = estimate.confidence
    }
}

/// Wire format for a persisted `ScheduledBlock` (spec §4.1 / §12). Returned by
/// `schedule.planDay`, `schedule.acceptBlock`, and `schedule.rejectBlock`.
public struct ScheduledBlockDTO: Codable, Sendable, Equatable {
    public let id: String
    public let taskID: String
    public let title: String
    public let start: String
    public let end: String
    public let status: String
    public let origin: String
    public let externalEventID: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, start, end, status, origin
        case taskID = "task_id"
        case externalEventID = "external_event_id"
    }

    public init(
        id: String,
        taskID: String,
        title: String,
        start: String,
        end: String,
        status: String,
        origin: String,
        externalEventID: String?
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.start = start
        self.end = end
        self.status = status
        self.origin = origin
        self.externalEventID = externalEventID
    }

    @MainActor
    public init(from block: ScheduledBlock) {
        self.id = block.id.uuidString
        self.taskID = block.taskID.uuidString
        self.title = block.title
        self.start = ScheduleDTOFormatter.string(block.start)
        self.end = ScheduleDTOFormatter.string(block.end)
        self.status = block.status.rawValue
        self.origin = block.origin.rawValue
        self.externalEventID = block.externalEventID
    }
}

/// Wire format for `schedule.planDay`: the freshly persisted proposed blocks plus
/// the overload guardrail (spec §6).
public struct PlanDayResponseDTO: Codable, Sendable, Equatable {
    public let proposals: [ScheduledBlockDTO]
    public let overload: OverloadReportDTO

    public init(proposals: [ScheduledBlockDTO], overload: OverloadReportDTO) {
        self.proposals = proposals
        self.overload = overload
    }
}

/// Wire format for the scheduler's overload guardrail (spec §6).
public struct OverloadReportDTO: Codable, Sendable, Equatable {
    public let totalEstimatedSeconds: Int
    public let totalFreeSeconds: Int
    public let isOverloaded: Bool
    public let unplacedTaskIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case totalEstimatedSeconds = "total_estimated_seconds"
        case totalFreeSeconds = "total_free_seconds"
        case isOverloaded = "is_overloaded"
        case unplacedTaskIDs = "unplaced_task_ids"
    }

    public init(from report: OverloadReport) {
        self.totalEstimatedSeconds = report.totalEstimatedSeconds
        self.totalFreeSeconds = report.totalFreeSeconds
        self.isOverloaded = report.isOverloaded
        self.unplacedTaskIDs = report.unplacedTaskIDs.map(\.uuidString)
    }
}

/// Wire format for a `DeadlineRisk` (spec §19.1 / §12 `schedule.deadlineRisks`).
/// Read-only signal — never an auto-action.
public struct DeadlineRiskDTO: Codable, Sendable, Equatable {
    public let taskID: String
    public let severity: String
    public let projectedSlackHours: Double
    public let suggestedStartBy: String?

    private enum CodingKeys: String, CodingKey {
        case severity
        case taskID = "task_id"
        case projectedSlackHours = "projected_slack_hours"
        case suggestedStartBy = "suggested_start_by"
    }

    public init(from risk: DeadlineRisk) {
        self.taskID = risk.taskID.uuidString
        self.severity = risk.severity.rawValue
        self.projectedSlackHours = risk.projectedSlackHours
        self.suggestedStartBy = risk.suggestedStartBy.map(ScheduleDTOFormatter.string)
    }
}

/// Shared ISO8601 formatting for the schedule / calendar DTOs. Fractional seconds
/// off for stable, human-readable wire timestamps (matches `TaskDTO`'s emit path).
public enum ScheduleDTOFormatter {
    public static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
