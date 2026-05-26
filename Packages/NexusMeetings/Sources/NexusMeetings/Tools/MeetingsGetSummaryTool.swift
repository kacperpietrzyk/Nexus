import Foundation
import NexusAgentTools
import NexusCore

public struct MeetingsGetSummaryTool: AgentTool {
    public let name = "meetings.get_summary"
    public let description = "Returns the generated summary for one meeting."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "meetingID": .string(description: "Meeting UUID.")
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
        let meeting = try MeetingRepository(context: contextRef.context).existingMeeting(id: id)
        return try MeetingsToolJSON.encode(
            SummaryResponse(
                meetingID: meeting.id.uuidString,
                title: meeting.title,
                summary: meeting.summaryText,
                languageCode: meeting.languageCode,
                providerProfile: meeting.providerProfile
            )
        )
    }

    private struct SummaryResponse: Codable, Equatable {
        let meetingID: String
        let title: String
        let summary: String
        let languageCode: String?
        let providerProfile: String
    }
}
