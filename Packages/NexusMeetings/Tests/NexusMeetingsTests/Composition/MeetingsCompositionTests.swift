import Foundation
import NexusAI
import NexusCore
import Testing

@testable import NexusMeetings

@MainActor
@Suite("MeetingsComposition")
struct MeetingsCompositionTests {
    @Test func exposesMeetingModelsForHostContainers() {
        #expect(MeetingsComposition.extraModels.map { "\($0)" }.contains("Meeting"))
        #expect(MeetingsComposition.localOnlyExtraModels.map { "\($0)" }.contains("MeetingAudioStorage"))
    }

    @Test func buildsAgentToolsWithoutNexusAgentDependency() throws {
        let context = try MeetingsTestSupport.makeContext()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NexusMeetingsComposition-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let composition = try MeetingsComposition(
            context: context,
            router: StaticMeetingProcessingRouter(),
            rootAudioFolder: folder,
            calendarProvider: MockCalendarEventProvider()
        )

        let toolNames = composition.agentTools().map(\.name).sorted()

        #expect(
            toolNames == [
                "meetings.action_items_for_meeting",
                "meetings.create",
                "meetings.delete",
                "meetings.get_summary",
                "meetings.get_transcript",
                "meetings.list_by_date",
                "meetings.recent",
                "meetings.search",
                "meetings.update",
            ])
    }
}

private struct StaticMeetingProcessingRouter: MeetingProcessingRouting {
    func route(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "[]", providerUsed: .appleIntelligence)
    }
}
