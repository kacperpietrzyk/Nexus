import Foundation

@MainActor
public protocol MeetingRecordingStarting: AnyObject {
    func start(meetingID: UUID, pid: pid_t) throws -> RecordingHandle
    func stop() throws
    func currentHandle() -> RecordingHandle?
    var isPaused: Bool { get }
    func pause() throws
    func resume() throws
}

extension MeetingRecordingStarting {
    public var isPaused: Bool { false }
    public func pause() throws {}
    public func resume() throws {}
}

@MainActor
public protocol MeetingPersisting: AnyObject {
    func insert(_ meeting: Meeting) throws
    func upsert(_ meeting: Meeting) throws
    func find(id: UUID) throws -> Meeting?
    func delete(id: UUID) throws
}

@MainActor
public protocol MeetingAudioStoragePersisting: AnyObject {
    func insert(_ storage: MeetingAudioStorage) throws
    func find(meetingID: UUID) throws -> MeetingAudioStorage?
}

extension MeetingRecorder: MeetingRecordingStarting {}
extension MeetingRepository: MeetingPersisting {}
extension MeetingAudioStorageRepository: MeetingAudioStoragePersisting {}

public enum MeetingRecordingServiceError: Error, Equatable {
    case recordingMissing
    case recordingMismatch
    case meetingMissing
    case storageMissing
}

public struct StoppedMeetingRecording {
    public let meeting: Meeting
    public let audioFolder: URL
}

@MainActor
public final class MeetingRecordingService {
    private let recorder: any MeetingRecordingStarting
    private let meetingRepository: any MeetingPersisting
    private let audioStorageRepository: any MeetingAudioStoragePersisting
    private let metadataStore: RecordingMetadataStore
    private let now: @MainActor () -> Date
    private let retentionPolicyProvider: @MainActor () -> MeetingAudioStorage.RetentionPolicy

    public init(
        recorder: any MeetingRecordingStarting,
        meetingRepository: any MeetingPersisting,
        audioStorageRepository: any MeetingAudioStoragePersisting,
        metadataStore: RecordingMetadataStore = RecordingMetadataStore(),
        retentionPolicyProvider: @escaping @MainActor () -> MeetingAudioStorage.RetentionPolicy = { .days30 },
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.meetingRepository = meetingRepository
        self.audioStorageRepository = audioStorageRepository
        self.metadataStore = metadataStore
        self.retentionPolicyProvider = retentionPolicyProvider
        self.now = now
    }

    public func startRecording(
        detectionSource: MeetingDetectionSource,
        appBundleID: String?,
        suggestedTitle: String?,
        pid: pid_t
    ) throws -> MeetingHandlePayload {
        let startedAt = now()
        let meeting = Meeting(
            title: Self.title(from: suggestedTitle, now: startedAt),
            startedAt: startedAt,
            appBundleID: appBundleID,
            detectionSource: detectionSource
        )

        var insertedMeetingID: UUID?
        var startedHandle: RecordingHandle?
        do {
            try meetingRepository.insert(meeting)
            insertedMeetingID = meeting.id

            let handle = try recorder.start(meetingID: meeting.id, pid: pid)
            startedHandle = handle

            let storage = MeetingAudioStorage(
                meetingID: meeting.id,
                folderURL: handle.folder,
                retentionPolicy: retentionPolicyProvider()
            )
            try audioStorageRepository.insert(storage)
            try metadataStore.writeStarted(meeting: meeting, folder: handle.folder)

            return MeetingHandlePayload(meetingID: meeting.id, folderPath: handle.folder.path)
        } catch {
            rollback(meetingID: insertedMeetingID, startedHandle: startedHandle)
            throw error
        }
    }

    public func stopRecording(meetingID: UUID) throws -> StoppedMeetingRecording {
        guard let handle = recorder.currentHandle() else {
            throw MeetingRecordingServiceError.recordingMissing
        }
        guard handle.meetingID == meetingID else {
            throw MeetingRecordingServiceError.recordingMismatch
        }

        try recorder.stop()

        guard let meeting = try meetingRepository.find(id: meetingID) else {
            throw MeetingRecordingServiceError.meetingMissing
        }
        guard let storage = try audioStorageRepository.find(meetingID: meetingID) else {
            throw MeetingRecordingServiceError.storageMissing
        }

        let endedAt = now()
        meeting.endedAt = endedAt
        meeting.durationSec = max(0, Int(endedAt.timeIntervalSince(meeting.startedAt)))
        meeting.processingStatus = MeetingProcessingStatus.queued.rawValue
        try meetingRepository.upsert(meeting)
        try metadataStore.markRecordingStopped(meeting: meeting, folder: storage.folderURL, stoppedAt: endedAt)

        return StoppedMeetingRecording(meeting: meeting, audioFolder: storage.folderURL)
    }

    /// Pause the active recording, validating it is the requested meeting.
    /// Idempotent: pausing an already-paused recording is a no-op.
    public func pauseRecording(meetingID: UUID) throws {
        try validateActive(meetingID: meetingID)
        try recorder.pause()
    }

    /// Resume the active recording, validating it is the requested meeting.
    /// Idempotent: resuming a running recording is a no-op.
    public func resumeRecording(meetingID: UUID) throws {
        try validateActive(meetingID: meetingID)
        try recorder.resume()
    }

    private func validateActive(meetingID: UUID) throws {
        guard let handle = recorder.currentHandle() else {
            throw MeetingRecordingServiceError.recordingMissing
        }
        guard handle.meetingID == meetingID else {
            throw MeetingRecordingServiceError.recordingMismatch
        }
    }

    private func rollback(meetingID: UUID?, startedHandle: RecordingHandle?) {
        if let startedHandle, recorder.currentHandle()?.meetingID == startedHandle.meetingID {
            try? recorder.stop()
            try? FileManager.default.removeItem(at: startedHandle.folder)
        }
        if let meetingID {
            try? meetingRepository.delete(id: meetingID)
        }
    }

    private static func title(from suggestedTitle: String?, now: Date) -> String {
        let trimmed = suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Meeting \(now)" }
        return trimmed
    }
}
