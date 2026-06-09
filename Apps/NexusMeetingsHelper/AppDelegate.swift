import AppKit
import NexusMeetings
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: HelperComposition?
    private var detectionTask: Task<Void, Never>?
    private var recordingRefreshTask: Task<Void, Never>?
    private var detectionWindow: DetectionNotificationWindow?
    private var recordingPanel: RecordingPanelWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        do {
            let composition = try HelperComposition()
            self.composition = composition
            composition.readinessCoordinator.start()
            startDetectionLoop(composition)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        detectionTask?.cancel()
        recordingRefreshTask?.cancel()
    }

    private func startDetectionLoop(_ composition: HelperComposition) {
        detectionTask = Task { @MainActor in
            for await event in composition.meetingsComposition.detector.events() {
                presentDetectionToast(event, composition: composition)
            }
        }
    }

    @MainActor
    private func presentDetectionToast(_ event: MeetingDetectionEvent, composition: HelperComposition) {
        composition.statusBar.update(state: .detection)
        var window: DetectionNotificationWindow?
        // `[weak window]` is essential: the panel retains its hosting
        // controller → `DetectionNotificationView` → these closures, so a strong
        // capture of `window` (the panel) would form a retain cycle and leak a
        // window + view per detected meeting.
        let view = DetectionNotificationView(
            appName: event.bundleID,
            meetingTitle: event.suggestedTitle,
            onStart: { [weak self, weak composition, weak window] in
                window?.orderOut(nil)
                guard let composition else { return }
                self?.startRecording(event: event, composition: composition)
            },
            onDismiss: { [weak self, weak composition, weak window] in
                window?.orderOut(nil)
                self?.detectionWindow = nil
                composition?.statusBar.update(state: .idle)
            }
        )
        let panel = DetectionNotificationWindow(view: view)
        window = panel
        detectionWindow = panel
        if let screen = NSScreen.main {
            panel.present(on: screen)
        }
    }

    @MainActor
    private func startRecording(event: MeetingDetectionEvent, composition: HelperComposition) {
        composition.startRecording(from: event) { [weak self, weak composition] handle, error in
            guard let self, let composition else { return }
            if let error {
                NSAlert(error: error).runModal()
                composition.statusBar.update(state: .idle)
                return
            }
            guard let handle else { return }
            Self.postOpenMeetingNotification(meetingID: handle.meetingID)
            composition.statusBar.update(state: .recording(elapsedSec: 0))
            showRecordingPanel(
                title: event.suggestedTitle,
                handle: handle,
                composition: composition
            )
        }
    }

    @MainActor
    private func showRecordingPanel(
        title: String,
        handle: MeetingHandlePayload,
        composition: HelperComposition
    ) {
        var panel: RecordingPanelWindow?
        let state = RecordingPanelState(title: title)
        // `[weak panel]` for the same reason as the detection toast: the panel
        // retains these closures via its hosting view, so a strong capture would
        // leak the recording panel.
        let view = RecordingPanelView(
            state: state,
            onStop: { [weak self, weak composition, weak panel] in
                guard let composition else { return }
                composition.stopRecording(meetingID: handle.meetingID) { error in
                    if let error {
                        NSAlert(error: error).runModal()
                        return
                    }
                    panel?.orderOut(nil)
                    self?.recordingPanel = nil
                    self?.recordingRefreshTask?.cancel()
                    self?.recordingRefreshTask = nil
                    composition.statusBar.update(state: .processing)
                }
            },
            onPause: {
                NSSound.beep()
            },
            onMinimize: { [weak panel] in
                panel?.orderOut(nil)
            }
        )
        let recordingPanel = RecordingPanelWindow(view: view)
        panel = recordingPanel
        self.recordingPanel = recordingPanel
        recordingPanel.center()
        recordingPanel.makeKeyAndOrderFront(nil)
        startRecordingPanelRefresh(state: state, composition: composition)
    }

    @MainActor
    private func startRecordingPanelRefresh(
        state: RecordingPanelState,
        composition: HelperComposition
    ) {
        recordingRefreshTask?.cancel()
        recordingRefreshTask = Task { @MainActor [weak state, weak composition] in
            while !Task.isCancelled {
                guard let state, let composition else { return }
                let snapshot = composition.currentRecordingState()
                guard snapshot.isRecording else {
                    // Recording stopped by a path other than the panel's Stop
                    // button (e.g. the capture service ended it). The panel's
                    // onStop sets `.processing`; mirror that here so the status
                    // bar doesn't stay stuck on `.recording`.
                    composition.statusBar.update(state: .processing)
                    return
                }
                state.apply(snapshot)
                composition.statusBar.update(state: .recording(elapsedSec: snapshot.elapsedSec))
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    nonisolated private static func postOpenMeetingNotification(meetingID: UUID) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.kacperpietrzyk.nexus.meetings.openMeeting"),
            object: nil,
            userInfo: ["meetingID": meetingID.uuidString],
            deliverImmediately: true
        )
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard
            let idString = response.notification.request.content.userInfo["meetingID"] as? String,
            let meetingID = UUID(uuidString: idString)
        else { return }
        Self.postOpenMeetingNotification(meetingID: meetingID)
    }
}
