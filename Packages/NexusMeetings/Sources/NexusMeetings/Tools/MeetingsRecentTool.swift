import Foundation
import NexusAgentTools
import NexusCore

public struct MeetingsRecentTool: AgentTool {
    public let name = "meetings.recent"
    public let description = "Returns the most recent meetings with title, date, duration, and summary excerpt."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "limit": .integer(minimum: 1, maximum: 50, description: "Maximum meetings to return. Defaults to 10.")
        ],
        required: []
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let limit = try MeetingsToolArguments.boundedInt(args["limit"], field: "limit", default: 10, range: 1...50)
        let repository = MeetingRepository(context: contextRef.context)
        let meetings = try repository.recent(limit: limit).filter { $0.deletedAt == nil }
        return try MeetingsToolJSON.encode(["meetings": meetings.map(MeetingSnapshotDTO.init(meeting:))])
    }
}
