import Foundation

public struct PlannedMeetingImport: Sendable, Equatable {
    /// Circleback numeric meeting id.
    public let externalID: Int
    /// Circleback alphanumeric / numeric-string linkId.
    public let externalLinkID: String
    /// "circleback:meeting:<id>" — value for Meeting.externalSourceID.
    public let externalSourceID: String
    public let title: String
    /// Approximated: circlebackCreatedAt − durationSec.
    public let startedAt: Date
    /// Naturally falls out as startedAt + durationSec == circlebackCreatedAt.
    public let endedAt: Date
    /// Raw createdAt from Circleback, kept for traceability.
    public let circlebackCreatedAt: Date
    public let durationSec: Int
    /// ReadMeetings.notes.
    public let summaryMarkdown: String
    public let attendees: [PlannedAttendee]
    /// Rendered from segments into a single text blob for Meeting.transcriptText.
    public let transcriptText: String
    public let transcriptSegments: [PlannedTranscriptSegment]
    public let actionItems: [PlannedActionItem]
    /// Path within the bundle for skip-log diagnostics.
    public let sourceFilePath: String

    public init(
        externalID: Int,
        externalLinkID: String,
        externalSourceID: String,
        title: String,
        startedAt: Date,
        endedAt: Date,
        circlebackCreatedAt: Date,
        durationSec: Int,
        summaryMarkdown: String,
        attendees: [PlannedAttendee],
        transcriptText: String,
        transcriptSegments: [PlannedTranscriptSegment],
        actionItems: [PlannedActionItem],
        sourceFilePath: String
    ) {
        self.externalID = externalID
        self.externalLinkID = externalLinkID
        self.externalSourceID = externalSourceID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.circlebackCreatedAt = circlebackCreatedAt
        self.durationSec = durationSec
        self.summaryMarkdown = summaryMarkdown
        self.attendees = attendees
        self.transcriptText = transcriptText
        self.transcriptSegments = transcriptSegments
        self.actionItems = actionItems
        self.sourceFilePath = sourceFilePath
    }
}

public struct PlannedAttendee: Sendable, Equatable {
    public let name: String
    public let email: String?

    public init(name: String, email: String?) {
        self.name = name
        self.email = email
    }
}

public struct PlannedTranscriptSegment: Sendable, Equatable {
    public let speaker: String
    public let text: String
    /// Single timestamp; end is inferred from next segment in the importer.
    public let startSec: Double

    public init(speaker: String, text: String, startSec: Double) {
        self.speaker = speaker
        self.text = text
        self.startSec = startSec
    }
}

public struct PlannedActionItem: Sendable, Equatable {
    /// Circleback action-item id.
    public let externalID: Int
    /// "circleback:actionItem:<id>" — value for TaskItem.externalSourceID.
    public let externalSourceID: String
    public let title: String
    public let description: String
    public let assigneeName: String?
    public let assigneeEmail: String?
    public let status: PlannedActionItemStatus
    /// Present only if status == .done — copied to TaskItem.lastCompletedAt.
    public let completedAt: Date?
    /// From global SearchActionItems; nil if only nested-shape was available.
    public let circlebackCreatedAt: Date?

    public init(
        externalID: Int,
        externalSourceID: String,
        title: String,
        description: String,
        assigneeName: String?,
        assigneeEmail: String?,
        status: PlannedActionItemStatus,
        completedAt: Date?,
        circlebackCreatedAt: Date?
    ) {
        self.externalID = externalID
        self.externalSourceID = externalSourceID
        self.title = title
        self.description = description
        self.assigneeName = assigneeName
        self.assigneeEmail = assigneeEmail
        self.status = status
        self.completedAt = completedAt
        self.circlebackCreatedAt = circlebackCreatedAt
    }
}

public enum PlannedActionItemStatus: String, Sendable, Equatable {
    case pending
    case done
}

public struct SkippedMeetingReason: Sendable, Equatable {
    public let sourceFilePath: String
    public let reason: String

    public init(sourceFilePath: String, reason: String) {
        self.sourceFilePath = sourceFilePath
        self.reason = reason
    }
}

public struct CirclebackImportPlan: Sendable {
    public let meetings: [PlannedMeetingImport]
    public let skipped: [SkippedMeetingReason]

    public init(meetings: [PlannedMeetingImport], skipped: [SkippedMeetingReason]) {
        self.meetings = meetings
        self.skipped = skipped
    }
}

public struct CirclebackImportResult: Sendable {
    public let importedCount: Int
    public let skippedCount: Int
    public let actionItemsCreated: Int
    /// Count of imported items whose TaskItem was created in .done status.
    public let actionItemsAlreadyDone: Int
    public let errors: [String]

    public init(
        importedCount: Int,
        skippedCount: Int,
        actionItemsCreated: Int,
        actionItemsAlreadyDone: Int,
        errors: [String]
    ) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.actionItemsCreated = actionItemsCreated
        self.actionItemsAlreadyDone = actionItemsAlreadyDone
        self.errors = errors
    }
}
