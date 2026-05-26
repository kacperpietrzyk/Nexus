import Foundation
import NexusMeetings

@MainActor
final class HelperToastBridge {
    private let xpcClient: MeetingsHelperXPCClient
    private let router: MeetingNavigationRouter
    private var observer: NSObjectProtocol?

    init(xpcClient: MeetingsHelperXPCClient, router: MeetingNavigationRouter) {
        self.xpcClient = xpcClient
        self.router = router
    }

    func start() {
        guard observer == nil else { return }
        _ = xpcClient
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
