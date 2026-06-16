import Foundation

/// Runs in the main app, which owns the resident Gemma model. Observes the
/// helper's `needsExternalSummary` notification (and sweeps at launch for
/// meetings left awaiting while the app was closed), compare-and-set claims each
/// one, and enqueues the summary/action-items continuation through the app's
/// MLX/Gemma-backed pipeline.
@MainActor
public final class MeetingSummaryClaimer {
    private let pendingMeetings: () -> [Meeting]
    private let find: (UUID) -> Meeting?
    private let claim: (Meeting) -> Void
    private let runContinuation: (UUID, URL) -> Void
    private let folderForMeeting: (UUID) -> URL
    private var observer: NSObjectProtocol?

    public init(
        pendingMeetings: @escaping () -> [Meeting],
        find: @escaping (UUID) -> Meeting?,
        claim: @escaping (Meeting) -> Void,
        runContinuation: @escaping (UUID, URL) -> Void,
        folderForMeeting: @escaping (UUID) -> URL
    ) {
        self.pendingMeetings = pendingMeetings
        self.find = find
        self.claim = claim
        self.runContinuation = runContinuation
        self.folderForMeeting = folderForMeeting
    }

    public func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: MeetingSummaryHandoffNotification.needsExternalSummary,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let parsed = MeetingSummaryHandoffNotification.parse(note) else { return }
            Task { @MainActor [weak self] in
                self?.claimAndRun(meetingID: parsed.id, audioFolder: parsed.folder)
            }
        }
        sweep()
    }

    public func sweep() {
        for meeting in pendingMeetings() where SummaryClaimDecision.canClaim(currentStatus: meeting.processingStatus) {
            claimAndRun(meetingID: meeting.id, audioFolder: folderForMeeting(meeting.id))
        }
    }

    public func claimAndRun(meetingID: UUID, audioFolder: URL) {
        guard let meeting = find(meetingID) else { return }
        guard SummaryClaimDecision.canClaim(currentStatus: meeting.processingStatus) else { return }
        claim(meeting)
        runContinuation(meetingID, audioFolder)
    }
}

extension MeetingSummaryClaimer {
    /// Binds the claimer to the live pipeline/repository/queue. `rootFolder` must
    /// be the same meetings audio root the recorder writes into, so launch-sweep
    /// meetings resolve to the right folder (the notification carries the live
    /// path for the hot path).
    public convenience init(
        pipeline: MeetingProcessingPipeline,
        repo: MeetingRepository,
        queue: PipelineQueue,
        rootFolder: URL
    ) {
        self.init(
            pendingMeetings: { (try? repo.recent(limit: 50)) ?? [] },
            find: { try? repo.find(id: $0) },
            claim: { meeting in
                meeting.processingStatus = MeetingProcessingStatus.claimedExternalSummary.rawValue
                meeting.updatedAt = Date()
                try? repo.upsert(meeting)
            },
            runContinuation: { meetingID, folder in
                Task {
                    await queue.enqueue(meetingID: meetingID) {
                        guard let meeting = try? repo.find(id: meetingID) else { return }
                        try? await pipeline.processSummaryAndActions(meeting: meeting, audioFolder: folder)
                    }
                }
            },
            folderForMeeting: { rootFolder.appendingPathComponent($0.uuidString) }
        )
    }
}
