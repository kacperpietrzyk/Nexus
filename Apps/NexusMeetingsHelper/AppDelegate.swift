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
            // Present the Stop/Pause panel + status bar for EVERY recording start,
            // whether it began via detection or the in-app "Record" button. Without
            // this the app-initiated path recorded headless with no way to stop it.
            composition.setRecordingStartedHandler { [weak self] payload, title in
                guard let self, let composition = self.composition else { return }
                self.handleRecordingStarted(payload: payload, title: title, composition: composition)
            }
            startDetectionLoop(composition)
            if UserDefaultsHelperAutoRecordStore.shared.isEnabled() {
                AccessibilityPromptGate().promptIfNeeded()
            }
            observeAccessibilityRequests()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        detectionTask?.cancel()
        recordingRefreshTask?.cancel()
    }

    private func observeAccessibilityRequests() {
        DistributedNotificationCenter.default().addObserver(
            forName: MeetingsReadinessNotification.requestPermissions,
            object: nil,
            queue: .main
        ) { _ in
            // The app's readiness "Open Settings" asks us (the AX owner) to prompt.
            // Force the prompt regardless of the one-shot flag since the user
            // explicitly requested it.
            Task { @MainActor in
                AccessibilityPromptGate(hasPrompted: { false }, markPrompted: {}).promptIfNeeded()
            }
        }
    }

    private func startDetectionLoop(_ composition: HelperComposition) {
        detectionTask = Task { @MainActor in
            for await event in composition.meetingsComposition.detector.events() {
                // Suppress detection while a recording is already in progress. The
                // meeting window keeps matching the poller for the whole meeting, so
                // without this guard the detector re-emits every debounce window
                // (~60s) — popping a fresh "Start recording?" toast and flipping the
                // status bar away from `.recording` repeatedly. Covers recordings
                // started by detection AND by the in-app manual path (both set the
                // shared recorder state the helper reports here).
                guard composition.currentRecordingState().isRecording == false else { continue }
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
        composition.startRecording(from: event) { [weak composition] _, error in
            // Success UI (Stop/Pause panel + status bar + openMeeting) is presented
            // by the shared `onRecordingStarted` hook, so detection- and
            // app-initiated recordings behave identically. Only the failure path is
            // handled here.
            guard let composition else { return }
            if let error {
                NSAlert(error: error).runModal()
                composition.statusBar.update(state: .idle)
            }
        }
    }

    /// Shared success presenter for a started recording, invoked by the helper's
    /// `onRecordingStarted` hook for both the detection and app-initiated paths.
    @MainActor
    private func handleRecordingStarted(
        payload: MeetingHandlePayload,
        title: String,
        composition: HelperComposition
    ) {
        Self.postOpenMeetingNotification(meetingID: payload.meetingID)
        composition.statusBar.update(state: .recording(elapsedSec: 0))
        showRecordingPanel(title: title, handle: payload, composition: composition)
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
            onPause: { [weak composition, weak state] in
                guard let composition, let state else { return }
                let wasPaused = state.isPaused
                let reply: (Error?) -> Void = { error in
                    if let error {
                        NSAlert(error: error).runModal()
                        return
                    }
                    // Reflect the new state immediately; the refresh loop also
                    // mirrors `isPaused` from the next snapshot.
                    state.isPaused = !wasPaused
                }
                if wasPaused {
                    composition.resumeRecording(meetingID: handle.meetingID, reply: reply)
                } else {
                    composition.pauseRecording(meetingID: handle.meetingID, reply: reply)
                }
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
