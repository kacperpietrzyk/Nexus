import Foundation
import NexusMeetings
import os

@MainActor
final class ManualRecordingStarter {
    private let xpcClient: MeetingsHelperXPCClient
    private let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "ManualRecording")

    init(xpcClient: MeetingsHelperXPCClient) {
        self.xpcClient = xpcClient
    }

    /// Registers the helper on demand (it may be unregistered when auto-record
    /// is off), then asks it to present the system content-sharing picker. No
    /// Accessibility permission required — the user picks the window directly.
    func startWithPicker() {
        MeetingsHelperSMAppServiceManager.registerIfNeeded()
        xpcClient.connect().startRecordingWithPicker { [logger] payload, error in
            if let error {
                logger.error("Manual recording failed: \(error.localizedDescription, privacy: .public)")
            } else if payload == nil {
                logger.info("Manual recording: picker dismissed")
            }
        }
    }
}
