import Foundation
import NexusAgentTools
import NexusCore

@MainActor
public enum MeetingsAgentTools {
    public static func tools(
        meetingRepository: MeetingRepository,
        taskRepository: TaskItemRepository? = nil,
        linkRepository: LinkRepository? = nil
    ) -> [any AgentTool] {
        [
            MeetingsSearchTool(repository: meetingRepository),
            MeetingsRecentTool(repository: meetingRepository),
            MeetingsListByDateTool(repository: meetingRepository),
            MeetingsGetSummaryTool(repository: meetingRepository),
            MeetingsGetTranscriptTool(repository: meetingRepository),
            MeetingsActionItemsForMeetingTool(
                meetingRepository: meetingRepository,
                taskRepository: taskRepository,
                linkRepository: linkRepository
            ),
        ]
    }
}
