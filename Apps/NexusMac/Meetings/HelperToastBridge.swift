import Foundation
import NexusMeetings

@MainActor
final class HelperToastBridge: MeetingHelperControlling {
    private let xpcClient: MeetingsHelperXPCClient
    private let router: MeetingNavigationRouter
    private var observer: NSObjectProtocol?

    init(xpcClient: MeetingsHelperXPCClient, router: MeetingNavigationRouter) {
        self.xpcClient = xpcClient
        self.router = router
    }

    /// App→helper control path: the helper owns the recordings and its own
    /// processing queue, so cancelling processing must go over XPC. This is the
    /// real control action that drives the otherwise-held XPC client.
    func cancelProcessing(meetingID: UUID) {
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
