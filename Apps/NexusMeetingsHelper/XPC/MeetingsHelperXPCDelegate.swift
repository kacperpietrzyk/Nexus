import Foundation
import NexusMeetings

final class MeetingsHelperXPCDelegate: NSObject, NSXPCListenerDelegate, MeetingsHelperXPCProtocol, @unchecked Sendable {
    private enum ErrorCode: Int {
        case pickerUnavailable = -100
        case pauseUnsupported = -200
        case resumeUnsupported = -201
        case invalidMeetingID = -300
        case meetingMissing = -301
        case storageMissing = -302
        case cancellationUnsupported = -303
        case recordingMissing = -304
        case recordingMismatch = -305
    }

    private static let errorDomain = "NexusMeetingsHelper.XPC"

    private let recorder: MeetingRecorder
    private let pipeline: MeetingProcessingPipeline
    private let pipelineQueue: PipelineQueue
    private let meetingRepository: MeetingRepository
    private let audioStorageRepository: MeetingAudioStorageRepository
    private let recordingService: MeetingRecordingService
    private let connectionValidator: MeetingsHelperXPCConnectionValidator
    private let now: @MainActor () -> Date

    @MainActor
    init(
        recorder: MeetingRecorder,
        pipeline: MeetingProcessingPipeline,
        pipelineQueue: PipelineQueue,
        meetingRepository: MeetingRepository,
        audioStorageRepository: MeetingAudioStorageRepository,
        connectionValidator: MeetingsHelperXPCConnectionValidator = MeetingsHelperXPCConnectionValidator(),
        retentionPolicyProvider: @escaping @MainActor () -> MeetingAudioStorage.RetentionPolicy = {
            UserDefaultsMeetingRetentionPolicyStore.shared.load()
        },
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.pipeline = pipeline
        self.pipelineQueue = pipelineQueue
        self.meetingRepository = meetingRepository
        self.audioStorageRepository = audioStorageRepository
        self.recordingService = MeetingRecordingService(
            recorder: recorder,
            meetingRepository: meetingRepository,
            audioStorageRepository: audioStorageRepository,
            retentionPolicyProvider: retentionPolicyProvider,
            now: now
        )
        self.connectionValidator = connectionValidator
        self.now = now
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
                reply.send(payload, nil)
            } catch {
                reply.send(nil, error)
            }
        }
    }

    func startRecordingWithPicker(reply: @escaping (MeetingHandlePayload?, Error?) -> Void) {
        reply(nil, Self.error(.pickerUnavailable, "Manual picker recording is not enabled yet."))
    }

    func stopRecording(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        let meetingID = meetingID as String
        let reply = ErrorReply(reply)
        Task { @MainActor in
            do {
                let id = try Self.uuid(from: meetingID)
                let stoppedRecording = try recordingService.stopRecording(meetingID: id)
                await pipelineQueue.enqueue { [pipeline] in
                    try? await pipeline.process(
                        meeting: stoppedRecording.meeting,
                        audioFolder: stoppedRecording.audioFolder
                    )
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
        reply(Self.error(.pauseUnsupported, "Pause is not supported by this helper build."))
    }

    func resumeRecording(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        reply(Self.error(.resumeUnsupported, "Resume is not supported by this helper build."))
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
            othersLevel: levels.othersLevel
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
                await pipelineQueue.enqueue { [pipeline] in
                    try? await pipeline.process(meeting: meeting, audioFolder: folder)
                }
                reply.send(nil)
            } catch {
                reply.send(error)
            }
        }
    }

    func cancelProcessing(meetingID: NSString, reply: @escaping (Error?) -> Void) {
        reply(Self.error(.cancellationUnsupported, "Pipeline cancellation is not implemented yet."))
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
