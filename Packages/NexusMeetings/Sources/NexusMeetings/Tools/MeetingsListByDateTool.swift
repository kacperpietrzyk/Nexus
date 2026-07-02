import Foundation
import NexusAgentTools
import NexusCore

public struct MeetingsListByDateTool: AgentTool {
    public let name = "meetings.list_by_date"
    public let description = "Lists meetings whose start time falls within an ISO8601 date range."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "from": .string(description: "Inclusive ISO8601 start date."),
            "to": .string(description: "Inclusive ISO8601 end date."),
        ],
        required: ["from", "to"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let from = try MeetingsToolArguments.requiredDate(args["from"], field: "from")
        let to = try MeetingsToolArguments.requiredDate(args["to"], field: "to")
        guard from <= to else {
            throw AgentError.validation("from must be earlier than or equal to to")
        }

        let repository = MeetingRepository(context: contextRef.context)
        // Filter soft-deleted BEFORE dedup: dedupedByID() keeps the first occurrence
        // regardless of deletedAt, so a (deleted, live) ghost pair with equal startedAt
        // could otherwise keep the deleted twin and then drop it — hiding the live
        // meeting entirely. Order matches LiquidMeetingsModel.reload.
        let meetings = try repository.range(from: from, to: to)
            .filter { $0.deletedAt == nil }
            .dedupedByID()
        return try MeetingsToolJSON.encode(["meetings": meetings.map(MeetingSnapshotDTO.init(meeting:))])
    }
}
