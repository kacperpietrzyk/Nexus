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
            "speaker": .string(
                description:
                    "Optional speaker filter applied to returned segments. Matches a diarized token "
                    + "(e.g. \"Speaker_1\", \"Me\") or a labeled display name. Implies includeSegments."
            ),
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
        let speaker = args["speaker"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSpeaker = (speaker?.isEmpty == false) ? speaker : nil
        let includeSegments =
            try MeetingsToolArguments.optionalBool(
                args["includeSegments"],
                field: "includeSegments",
                default: false
            ) || normalizedSpeaker != nil
        let meeting = try MeetingRepository(context: contextRef.context).existingMeeting(id: id)
        let segments: [MeetingSpeakerSegment]?
        if includeSegments {
            let decoded = (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? []
            if let normalizedSpeaker {
                let participants = (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
                segments = MergeStage.segments(decoded, forSpeaker: normalizedSpeaker, participants: participants)
            } else {
                segments = decoded
            }
        } else {
            segments = nil
        }
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
