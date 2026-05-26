import Foundation
import NexusAgentTools
import NexusCore

public struct MeetingsGetTranscriptTool: AgentTool {
    public let name = "meetings.get_transcript"
    public let description = "Returns the transcript for one meeting, optionally including speaker segments."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "meetingID": .string(description: "Meeting UUID."),
            "includeSegments": .boolean(description: "Include decoded speaker segments. Defaults to false."),
        ],
        required: ["meetingID"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let id = try MeetingsToolArguments.requiredUUID(args["meetingID"], field: "meetingID")
        let includeSegments = try MeetingsToolArguments.optionalBool(
            args["includeSegments"],
            field: "includeSegments",
            default: false
        )
        let meeting = try MeetingRepository(context: contextRef.context).existingMeeting(id: id)
        let segments = includeSegments ? (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? [] : nil
        return try MeetingsToolJSON.encode(
            TranscriptResponse(
                meetingID: meeting.id.uuidString,
                title: meeting.title,
                transcript: meeting.transcriptText,
                segments: segments
            )
        )
    }

    private struct TranscriptResponse: Codable, Equatable {
        let meetingID: String
        let title: String
        let transcript: String
        let segments: [MeetingSpeakerSegment]?
    }
}
