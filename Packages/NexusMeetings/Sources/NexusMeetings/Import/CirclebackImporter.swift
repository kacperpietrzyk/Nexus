import Foundation
import NexusCore
import TasksFeature

@MainActor
public final class CirclebackImporter {
    private let meetingRepository: MeetingRepository
    private let taskRepository: TaskItemRepository
    private let linkRepository: LinkRepository
    private let parser: NexusExportFormat

    public init(
        meetingRepository: MeetingRepository,
        taskRepository: TaskItemRepository,
        linkRepository: LinkRepository,
        parser: NexusExportFormat = .init()
    ) {
        self.meetingRepository = meetingRepository
        self.taskRepository = taskRepository
        self.linkRepository = linkRepository
        self.parser = parser
    }

    public func plan(bundleURL: URL) throws -> CirclebackImportPlan {
        try parser.plan(bundleURL: bundleURL)
    }

    public func execute(
        bundleURL: URL,
        progress: @MainActor @escaping (Double) -> Void
    ) async throws -> CirclebackImportResult {
        let importPlan = try plan(bundleURL: bundleURL)
        var importedCount = 0
        var actionItemCount = 0
        var actionItemsAlreadyDone = 0
        var skippedCount = importPlan.skipped.count
        var errors: [String] = importPlan.skipped.map { "\($0.sourceFilePath): \($0.reason)" }
        let total = max(1, importPlan.meetings.count)

        let existingMeetingIDs = Set(
            try meetingRepository
                .allExternalSourceIDs(withPrefix: CirclebackExternalRef.meetingPrefix))
        var existingTaskIDs = Set(
            try taskRepository
                .allExternalSourceIDs(withPrefix: CirclebackExternalRef.actionItemPrefix))

        for (index, planned) in importPlan.meetings.enumerated() {
            await Task.yield()
            if existingMeetingIDs.contains(planned.externalSourceID) {
                skippedCount += 1
                progress(Double(index + 1) / Double(total))
                continue
            }
            let (done, created) = try importMeeting(planned, existingTaskIDs: &existingTaskIDs)
            actionItemCount += created
            actionItemsAlreadyDone += done
            importedCount += 1
            progress(Double(index + 1) / Double(total))
        }

        return CirclebackImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            actionItemsCreated: actionItemCount,
            actionItemsAlreadyDone: actionItemsAlreadyDone,
            errors: errors
        )
    }

    // Returns (doneCount, createdCount).
    private func importMeeting(
        _ planned: PlannedMeetingImport,
        existingTaskIDs: inout Set<String>
    ) throws -> (done: Int, created: Int) {
        let segmentsData = try MeetingSpeakerSegment.encode(
            makeSegments(
                from: planned.transcriptSegments,
                fallbackDurationMs: planned.durationSec * 1000
            ))
        let participantsData = try MeetingParticipant.encode(makeParticipants(from: planned.attendees))
        let meeting = Meeting(
            title: planned.title,
            startedAt: planned.startedAt,
            durationSec: planned.durationSec,
            endedAt: planned.endedAt,
            detectionSource: .imported,
            processingStatus: .ready,
            processedAt: Date(),
            transcriptText: planned.transcriptText,
            summaryText: planned.summaryMarkdown,
            segmentsJSON: segmentsData,
            participantsJSON: participantsData,
            providerProfile: "imported:circleback"
        )
        meeting.externalSourceID = planned.externalSourceID
        try meetingRepository.insert(meeting)

        var doneCount = 0
        var createdCount = 0
        for action in planned.actionItems {
            guard !existingTaskIDs.contains(action.externalSourceID) else { continue }
            let isDone = action.status == .done
            let task = TaskItem(
                title: action.title,
                body: action.description,
                status: isDone ? .done : .open
            )
            task.externalSourceID = action.externalSourceID
            if isDone, let completedAt = action.completedAt {
                task.lastCompletedAt = completedAt
            }
            try taskRepository.insert(task)
            existingTaskIDs.insert(action.externalSourceID)
            try linkRepository.findOrCreate(
                from: (.meeting, meeting.id),
                to: (.task, task.id),
                linkKind: .actionItem
            )
            meeting.actionItemIDs.append(task.id)
            createdCount += 1
            if isDone { doneCount += 1 }
        }
        try meetingRepository.upsert(meeting)
        return (doneCount, createdCount)
    }

    private func makeSegments(
        from planned: [PlannedTranscriptSegment],
        fallbackDurationMs: Int
    ) -> [MeetingSpeakerSegment] {
        guard !planned.isEmpty else { return [] }
        var out: [MeetingSpeakerSegment] = []
        for (i, segment) in planned.enumerated() {
            let startMs = Int((segment.startSec * 1000).rounded())
            let endMs: Int
            if i + 1 < planned.count {
                endMs = Int((planned[i + 1].startSec * 1000).rounded())
            } else {
                endMs = max(startMs + 1000, fallbackDurationMs)
            }
            out.append(
                MeetingSpeakerSegment(
                    startMs: startMs,
                    endMs: endMs,
                    speaker: segment.speaker,
                    text: segment.text
                ))
        }
        return out
    }

    private func makeParticipants(from attendees: [PlannedAttendee]) -> [MeetingParticipant] {
        attendees.map { attendee in
            let speakerID = attendee.name.replacingOccurrences(of: " ", with: "_")
            return MeetingParticipant(speakerID: speakerID, displayName: attendee.name)
        }
    }
}
