import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

public struct MeetingsActionItemsForMeetingTool: AgentTool {
    public let name = "meetings.action_items_for_meeting"
    public let description = "Returns non-deleted task action items linked from one meeting."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "meetingID": .string(description: "Meeting UUID.")
        ],
        required: ["meetingID"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(
        meetingRepository: MeetingRepository,
        taskRepository _: TaskItemRepository? = nil,
        linkRepository _: LinkRepository? = nil
    ) {
        self.contextRef = ModelContextRef(meetingRepository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let meetingID = try MeetingsToolArguments.requiredUUID(args["meetingID"], field: "meetingID")
        let context = contextRef.context
        _ = try MeetingRepository(context: context).existingMeeting(id: meetingID)

        let links = try LinkRepository(context: context)
            .outgoing(from: (.meeting, meetingID))
            .filter { $0.linkKind == .actionItem && $0.toKind == .task }
        let taskIDs = Set(links.map(\.toID))
        guard taskIDs.isEmpty == false else {
            return try MeetingsToolJSON.encode(["tasks": [MeetingTaskSnapshotDTO]()])
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let tasks = try context.fetch(descriptor)
            .filter { taskIDs.contains($0.id) }
            .map(MeetingTaskSnapshotDTO.init(task:))
        return try MeetingsToolJSON.encode(["tasks": tasks])
    }
}
