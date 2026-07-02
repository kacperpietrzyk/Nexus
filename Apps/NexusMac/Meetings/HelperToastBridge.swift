import Foundation
import NexusMeetings

@MainActor
final class HelperToastBridge: MeetingHelperControlling {
    private let xpcClient: MeetingsHelperXPCClient
    private let router: MeetingNavigationRouter
    private let appPipelineQueue: PipelineQueue
    private var observer: NSObjectProtocol?

    init(
        xpcClient: MeetingsHelperXPCClient,
        router: MeetingNavigationRouter,
        appPipelineQueue: PipelineQueue
    ) {
        self.xpcClient = xpcClient
        self.router = router
        self.appPipelineQueue = appPipelineQueue
    }

    /// Cancels processing on BOTH queues. Assistant-model (Gemma) summaries run on
    /// the app's OWN in-process `PipelineQueue` (the app owns Gemma), while
    /// transcription and Apple-Intelligence summaries run in the HELPER — and the
    /// meeting's `processing-*` status alone can't tell which queue owns the job.
    /// Cancelling the queue that isn't running it is a harmless no-op, so cancelling
    /// both guarantees the button actually stops the work it targets (previously it
    /// only hit the helper and silently no-op'd for app-run summaries).
    func cancelProcessing(meetingID: UUID) {
        Task { await appPipelineQueue.cancelProcessing(meetingID: meetingID) }
        xpcClient.connect().cancelProcessing(meetingID: meetingID.uuidString as NSString) { error in
            if let error {
                NSLog("Nexus meetings cancel-processing failed: %@", error.localizedDescription)
            }
        }
    }

    func start() {
        guard observer == nil else { return }
        let name = Notification.Name("com.kacperpietrzyk.nexus.meetings.openMeeting")
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let idString = note.userInfo?["meetingID"] as? String,
                let id = UUID(uuidString: idString)
            else { return }
            Task { @MainActor in
                self?.router.navigate(to: id)
            }
        }
    }
}
