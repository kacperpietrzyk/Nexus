import Foundation
import NexusMeetings

final class MeetingsHelperXPCService {
    private let listener: NSXPCListener
    private let delegate: MeetingsHelperXPCDelegate

    init(delegate: MeetingsHelperXPCDelegate) {
        listener = NSXPCListener(machServiceName: MeetingsHelperXPCClient.machServiceName)
        self.delegate = delegate
        listener.delegate = delegate
    }

    func resume() {
        listener.resume()
    }
}
