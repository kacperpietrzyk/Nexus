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

    /// Registers the helper on demand, then starts a recording with a global
    /// system-audio tap — Circleback-style "just hit record". No window picker
    /// and no per-app detection: the tap captures all output audio (every remote
    /// participant, native app or browser call) into `others.wav`. Passing
    /// `pid: 0` selects the global tap in the helper; no Screen Recording
    /// permission is involved (only the one-time audio-capture consent).
    func start() {
        MeetingsHelperSMAppServiceManager.registerIfNeeded()
        xpcClient.connect().startRecording(
            detectionSource: MeetingDetectionSource.manual.rawValue,
            appBundleID: nil,
            suggestedTitle: nil,
            pid: 0
        ) { [logger] payload, error in
            if let error {
                logger.error("Manual recording failed: \(error.localizedDescription, privacy: .public)")
            } else if payload == nil {
                logger.info("Manual recording: no handle returned")
            }
        }
    }
}
