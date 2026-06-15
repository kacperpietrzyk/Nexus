import Foundation
import NexusAgentTools
import NexusCore

private enum MeetingsWriteSupport {
    /// Parses an optional ISO8601 timestamp argument. Returns nil when the field
    /// is absent or empty; throws `AgentError.validation` when present but malformed.
    static func optionalDate(_ value: JSONValue?, field: String) throws -> Date? {
        guard let raw = value?.stringValue, raw.isEmpty == false else { return nil }
        guard let parsed = MeetingsToolFormatters.date(from: raw) else {
            throw AgentError.validation("Invalid ISO8601 date for field: \(field)")
        }
        return parsed
    }
}

public struct MeetingsCreateTool: AgentTool {
    public let name = "meetings.create"
    public let description = "Create a meeting record (manual source). Returns the new meeting id."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "title": .string(description: "Meeting title."),
            "started_at": .string(description: "ISO8601 start timestamp."),
            "ended_at": .string(description: "Optional ISO8601 end timestamp."),
            "summary": .string(description: "Optional summary text."),
            "transcript": .string(description: "Optional transcript text."),
        ],
        required: ["title", "started_at"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let title = try MeetingsToolArguments.requiredString(args["title"], field: "title")
        let startedAt = try MeetingsToolArguments.requiredDate(args["started_at"], field: "started_at")
        let endedAt = try MeetingsWriteSupport.optionalDate(args["ended_at"], field: "ended_at")
        if let endedAt, endedAt < startedAt {
            throw AgentError.validation("ended_at must not be before started_at")
        }
        let meeting = Meeting(
            title: title,
            startedAt: startedAt,
            durationSec: endedAt.map { Int($0.timeIntervalSince(startedAt)) } ?? 0,
            endedAt: endedAt,
            detectionSource: .manual,
            processingStatus: .ready,
            transcriptText: args["transcript"]?.stringValue ?? "",
            summaryText: args["summary"]?.stringValue ?? ""
        )
        try MeetingRepository(context: contextRef.context).insert(meeting)
        return .object(["id": .string(meeting.id.uuidString), "title": .string(meeting.title)])
    }
}

public struct MeetingsUpdateTool: AgentTool {
    public let name = "meetings.update"
    public let description = "Patch an existing meeting's title/summary/transcript/ended_at."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "meeting_id": .string(description: "Meeting UUID."),
            "title": .string(description: "Optional new title."),
            "summary": .string(description: "Optional new summary."),
            "transcript": .string(description: "Optional new transcript."),
            "ended_at": .string(description: "Optional ISO8601 end timestamp."),
        ],
        required: ["meeting_id"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let id = try MeetingsToolArguments.requiredUUID(args["meeting_id"], field: "meeting_id")
        let repo = MeetingRepository(context: contextRef.context)
        let meeting = try repo.existingMeeting(id: id)
        if let rawTitle = args["title"]?.stringValue {
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false else {
                throw AgentError.validation("title must not be empty")
            }
            meeting.title = title
        }
        if let summary = args["summary"]?.stringValue { meeting.summaryText = summary }
        if let transcript = args["transcript"]?.stringValue { meeting.transcriptText = transcript }
        if let ended = try MeetingsWriteSupport.optionalDate(args["ended_at"], field: "ended_at") {
            guard ended >= meeting.startedAt else {
                throw AgentError.validation("ended_at must not be before started_at")
            }
            meeting.endedAt = ended
            meeting.durationSec = Int(ended.timeIntervalSince(meeting.startedAt))
        }
        meeting.updatedAt = Date()
        try repo.upsert(meeting)
        return .object(["id": .string(meeting.id.uuidString), "title": .string(meeting.title)])
    }
}

public struct MeetingsDeleteTool: AgentTool {
    public let name = "meetings.delete"
    public let description = "Delete a meeting by UUID. This is permanent and cannot be undone."
    public let inputSchema: JSONSchema = .object(
        properties: ["meeting_id": .string(description: "Meeting UUID to delete.")],
        required: ["meeting_id"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let id = try MeetingsToolArguments.requiredUUID(args["meeting_id"], field: "meeting_id")
        try MeetingRepository(context: contextRef.context).delete(id: id)
        return .object(["success": .bool(true)])
    }
}
