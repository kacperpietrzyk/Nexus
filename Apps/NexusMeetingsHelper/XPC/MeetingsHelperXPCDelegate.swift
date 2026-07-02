import Foundation
import NexusMeetings

final class MeetingsHelperXPCDelegate: NSObject, NSXPCListenerDelegate, MeetingsHelperXPCProtocol, @unchecked Sendable {
    private enum ErrorCode: Int {
        case invalidMeetingID = -300
        case meetingMissing = -301
        case storageMissing = -302
        case recordingMissing = -304
        case recordingMismatch = -305
    }

    private static let errorDomain = "NexusMeetingsHelper.XPC"

    private let recorder: MeetingRecorder
    private let pipeline: MeetingProcessingPipeline
    private let pipelineQueue: PipelineQueue
    private let meetingRepository: MeetingRepository
    private let audioStorageRepository: MeetingAudioStorageRepository
    private let meetingProcessor: MeetingSummaryDeferralProcessor
    private let recordingService: MeetingRecordingService
    private let connectionValidator: MeetingsHelperXPCConnectionValidator
    private let now: @MainActor () -> Date
    // Recording-time screen-OCR driver (opt-in, spec §7). Self-gates on the OCR
    // toggle, so when the feature is OFF it never reads the screen.
    private let screenContextRecorder: ScreenContextRecorder
    // System content-sharing picker for manual app-driven recording.
    private let pickerPresenter: any ContentSharingPickerPresenting

    /// Fired on the main actor after ANY successful start (detection-initiated via
    /// `HelperComposition.startRecording`, or app-initiated directly over XPC), so
    /// the helper's AppDelegate presents the Stop/Pause panel + status bar + opens
    /// the meeting. Without this the app-initiated path recorded headless with no
    /// stop control and the meeting was never surfaced. The single hook keeps both
    /// entry points behaving identically.
    @MainActor var onRecordingStarted: ((MeetingHandlePayload, String) -> Void)?

    @MainActor
    init(
        recorder: MeetingRecorder,
        pipeline: MeetingProcessingPipeline,
        pipelineQueue: PipelineQueue,
        meetingRepository: MeetingRepository,
        audioStorageRepository: MeetingAudioStorageRepository,
        meetingProcessor: MeetingSummaryDeferralProcessor,
        connectionValidator: MeetingsHelperXPCConnectionValidator = MeetingsHelperXPCConnectionValidator(),
        retentionPolicyProvider: @escaping @MainActor () -> MeetingAudioStorage.RetentionPolicy = {
            UserDefaultsMeetingRetentionPolicyStore.shared.load()
        },
        screenContextRecorder: ScreenContextRecorder = MeetingsHelperXPCDelegate.makeScreenContextRecorder(),
        pickerPresenter: any ContentSharingPickerPresenting = ContentSharingPickerCapture(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.pipeline = pipeline
        self.pipelineQueue = pipelineQueue
        self.meetingRepository = meetingRepository
        self.audioStorageRepository = audioStorageRepository
        self.meetingProcessor = meetingProcessor
        self.recordingService = MeetingRecordingService(
            recorder: recorder,
            meetingRepository: meetingRepository,
            audioStorageRepository: audioStorageRepository,
            retentionPolicyProvider: retentionPolicyProvider,
            now: now
        )
        self.connectionValidator = connectionValidator
        self.screenContextRecorder = screenContextRecorder
        self.pickerPresenter = pickerPresenter
        self.now = now
    }

    /// Production screen-OCR driver: a ScreenCaptureKit + Vision capturer behind
    /// the standard ``ScreenContextStage``. The helper is macOS-only, so both
    /// frameworks are always available here.
    @MainActor
    static func makeScreenContextRecorder() -> ScreenContextRecorder {
        ScreenContextRecorder(stage: ScreenContextStage(capture: ScreenshotScreenContextCapture()))
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        guard connectionValidator.validate(processIdentifier: newConnection.processIdentifier) == .accepted else {
            newConnection.invalidate()
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: MeetingsHelperXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func startRecording(
        detectionSource: String,
        appBundleID: String?,
        suggestedTitle: String?,
        pid: Int32,
        reply: @escaping (MeetingHandlePayload?, Error?) -> Void
    ) {
        let reply = StartRecordingReply(reply)
        Task { @MainActor in
            do {
                let source = MeetingDetectionSource(rawValue: detectionSource) ?? .manual
                let payload = try recordingService.startRecording(
                    detectionSource: source,
                    appBundleID: appBundleID,
                    suggestedTitle: suggestedTitle,
                    pid: pid_t(pid)
                )
                // Begin recording-time screen OCR into the same folder (no-op
                // unless the opt-in toggle is on).
                screenContextRecorder.start(folder: URL(fileURLWithPath: payload.folderPath))
                reply.send(payload, nil)
                onRecordingStarted?(payload, resolvedTitle(suggestedTitle, meetingID: payload.meetingID))
            } catch {
                reply.send(nil, error)
            }
        }
    }

    /// Prefers an explicit suggested title, falling back to the persisted meeting
    /// title (then a generic label) so the recording panel always has a name.
    @MainActor
    private func resolvedTitle(_ suggested: String?, meetingID: UUID) -> String {
        if let trimmed = suggested?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        return (try? meetingRepository.find(id: meetingID))?.title ?? "Meeting"
    }

    func startRecordingWithPicker(reply: @escaping (MeetingHandlePayload?, Error?) -> Void) {
        let reply = StartRecordingReply(reply)
        Task { @MainActor in
            do {
                // Present the system content-sharing picker so the user chooses
                // the app/window to record; the choice supplies the bundle + pid.
                let selection = try await pickerPresenter.present()
                let payload = try recordingService.startRecording(
                    detectionSource: .manual,
                    appBundleID: selection.bundleID,
                    suggestedTitle: selection.displayName,
                    pid: selection.pid
                )
                screenContextRecorder.start(folder: URL(fileURLWithPath: payload.folderPath))
                reply.send(payload, nil)
                onRecordingStarted?(payload, resolvedTitle(selection.displayName, meetingID: payload.meetingID))
            } catch is CancellationError {
                // User dismissed the picker — not an error, just no recording.
                reply.send(nil, nil)
            } catch {
                reply.send(nil, error)
            }
        }
    }

    func stopRecording(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        let meetingID = meetingID as String
        let reply = ErrorReply(reply)
        Task { @MainActor in
            do {
                let id = try Self.uuid(from: meetingID)
                screenContextRecorder.stop()
                let stoppedRecording = try recordingService.stopRecording(meetingID: id)
                let meeting = stoppedRecording.meeting
                let audioFolder = stoppedRecording.audioFolder
                await pipelineQueue.enqueue(meetingID: id) { [meetingProcessor] in
                    await meetingProcessor.process(meeting: meeting, audioFolder: audioFolder)
                }
                reply.send(nil)
            } catch let error as MeetingRecordingServiceError {
                reply.send(Self.error(from: error))
            } catch {
                reply.send(error)
            }
        }
    }

    func pauseRecording(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        let meetingID = meetingID as String
        let reply = ErrorReply(reply)
        Task { @MainActor in
            do {
                let id = try Self.uuid(from: meetingID)
                try recordingService.pauseRecording(meetingID: id)
                screenContextRecorder.stop()
                reply.send(nil)
            } catch let error as MeetingRecordingServiceError {
                reply.send(Self.error(from: error))
            } catch {
                reply.send(error)
            }
        }
    }

    func resumeRecording(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        let meetingID = meetingID as String
        let reply = ErrorReply(reply)
        Task { @MainActor in
            do {
                let id = try Self.uuid(from: meetingID)
                try recordingService.resumeRecording(meetingID: id)
                if let folder = recorder.currentHandle()?.folder {
                    screenContextRecorder.start(folder: folder)
                }
                reply.send(nil)
            } catch let error as MeetingRecordingServiceError {
                reply.send(Self.error(from: error))
            } catch {
                reply.send(error)
            }
        }
    }

    func currentRecordingState(reply: @escaping (RecordingStateSnapshot) -> Void) {
        let reply = StateReply(reply)
        Task { @MainActor in
            reply.send(recordingStateSnapshot())
        }
    }

    @MainActor
    func recordingStateSnapshot() -> RecordingStateSnapshot {
        let handle = recorder.currentHandle()
        let elapsedSec: Int
        if let meetingID = handle?.meetingID, let meeting = try? meetingRepository.find(id: meetingID) {
            elapsedSec = max(0, Int(now().timeIntervalSince(meeting.startedAt)))
        } else {
            elapsedSec = 0
        }
        let levels = recorder.currentLevels()

        return RecordingStateSnapshot(
            isRecording: handle != nil,
            meetingID: handle?.meetingID,
            elapsedSec: elapsedSec,
            micLevel: levels.micLevel,
            othersLevel: levels.othersLevel,
            isPaused: recorder.isPaused
        )
    }

    func reprocess(meetingID: NSString, fromStage: NSString, reply: @escaping (Error?) -> Void) {
        let meetingID = meetingID as String
        let reply = ErrorReply(reply)
        Task { @MainActor in
            do {
                let id = try Self.uuid(from: meetingID)
                guard let meeting = try meetingRepository.find(id: id) else {
                    reply.send(Self.error(.meetingMissing, "Meeting was not found."))
                    return
                }
                guard let storage = try audioStorageRepository.find(meetingID: id) else {
                    reply.send(Self.error(.storageMissing, "Meeting audio storage was not found."))
                    return
                }

                let folder = storage.folderURL
                await pipelineQueue.enqueue(meetingID: id) { [pipeline] in
                    try? await pipeline.process(meeting: meeting, audioFolder: folder)
                }
                reply.send(nil)
            } catch {
                reply.send(error)
            }
        }
    }

    func cancelProcessing(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        let meetingID = meetingID as String
        let reply = ErrorReply(reply)
        Task { @MainActor in
            do {
                let id = try Self.uuid(from: meetingID)
                // Drops the meeting's queued job and cooperatively cancels it if it
                // is the one currently running (stops at the next stage boundary).
                await pipelineQueue.cancelProcessing(meetingID: id)
                reply.send(nil)
            } catch {
                reply.send(error)
            }
        }
    }

    private static func uuid(from value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw error(.invalidMeetingID, "Meeting ID is not a valid UUID.")
        }
        return id
    }

    private static func error(_ code: ErrorCode, _ message: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func error(from serviceError: MeetingRecordingServiceError) -> NSError {
        switch serviceError {
        case .recordingMissing:
            error(.recordingMissing, "No recording is active.")
        case .recordingMismatch:
            error(.recordingMismatch, "Requested meeting is not the active recording.")
        case .meetingMissing:
            error(.meetingMissing, "Meeting was not found.")
        case .storageMissing:
            error(.storageMissing, "Meeting audio storage was not found.")
        }
    }
}

private struct StartRecordingReply: @unchecked Sendable {
    let send: (MeetingHandlePayload?, Error?) -> Void

    init(_ send: @escaping (MeetingHandlePayload?, Error?) -> Void) {
        self.send = send
    }
}

private struct ErrorReply: @unchecked Sendable {
    let send: (Error?) -> Void

    init(_ send: @escaping (Error?) -> Void) {
        self.send = send
    }
}

private struct StateReply: @unchecked Sendable {
    let send: (RecordingStateSnapshot) -> Void

    init(_ send: @escaping (RecordingStateSnapshot) -> Void) {
        self.send = send
    }
}
