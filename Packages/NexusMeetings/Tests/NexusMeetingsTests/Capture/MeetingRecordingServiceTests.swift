import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func recordingServiceDeletesMeetingWhenRecorderStartFails() throws {
    let meetingRepository = InMemoryMeetingPersistence()
    let storageRepository = InMemoryMeetingAudioStoragePersistence()
    let recorder = StubRecordingStarter(startError: RecordingServiceTestError.startFailed)
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: meetingRepository,
        audioStorageRepository: storageRepository,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    #expect(throws: RecordingServiceTestError.startFailed) {
        try service.startRecording(
            detectionSource: .auto,
            appBundleID: "com.microsoft.teams2",
            suggestedTitle: "Planning",
            pid: 42
        )
    }

    #expect(meetingRepository.meetings.isEmpty)
    #expect(storageRepository.storages.isEmpty)
}

@MainActor
@Test func recordingServiceStopsRecorderAndDeletesMeetingWhenStorageInsertFails() throws {
    let meetingRepository = InMemoryMeetingPersistence()
    let storageRepository = InMemoryMeetingAudioStoragePersistence(
        insertError: RecordingServiceTestError.storageFailed
    )
    let rootFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingRecordingServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootFolder) }

    let recorder = StubRecordingStarter(rootFolder: rootFolder)
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: meetingRepository,
        audioStorageRepository: storageRepository,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    #expect(throws: RecordingServiceTestError.storageFailed) {
        try service.startRecording(
            detectionSource: .auto,
            appBundleID: "com.microsoft.teams2",
            suggestedTitle: "Planning",
            pid: 42
        )
    }

    #expect(recorder.stopCallCount == 1)
    #expect(meetingRepository.meetings.isEmpty)
    #expect(storageRepository.storages.isEmpty)
    #expect(recorder.startedFolder.map { FileManager.default.fileExists(atPath: $0.path) } == false)
}

@MainActor
@Test func recordingServiceStopsMatchingRecorderBeforeReturningMissingMeetingError() throws {
    let meetingRepository = InMemoryMeetingPersistence()
    let storageRepository = InMemoryMeetingAudioStoragePersistence()
    let meetingID = UUID()
    let recorder = StubRecordingStarter(
        activeHandle: RecordingHandle(
            meetingID: meetingID,
            folder: URL(fileURLWithPath: "/tmp/\(meetingID.uuidString)")
        )
    )
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: meetingRepository,
        audioStorageRepository: storageRepository,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    #expect(throws: MeetingRecordingServiceError.meetingMissing) {
        try service.stopRecording(meetingID: meetingID)
    }

    #expect(recorder.stopCallCount == 1)
    #expect(recorder.currentHandle() == nil)
}

@MainActor
@Test func recordingServicePersistsMeetingAndStorageOnSuccess() throws {
    let meetingRepository = InMemoryMeetingPersistence()
    let storageRepository = InMemoryMeetingAudioStoragePersistence()
    let recorder = StubRecordingStarter()
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: meetingRepository,
        audioStorageRepository: storageRepository,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let payload = try service.startRecording(
        detectionSource: .auto,
        appBundleID: "com.microsoft.teams2",
        suggestedTitle: "Planning",
        pid: 42
    )

    #expect(meetingRepository.meetings.count == 1)
    #expect(storageRepository.storages.count == 1)
    #expect(payload.meetingID == meetingRepository.meetings[0].id)
    #expect(payload.folderPath == "/tmp/\(payload.meetingID.uuidString)")
}

@MainActor
@Test func recordingServiceUsesRetentionPolicyProviderForNewStorage() throws {
    let meetingRepository = InMemoryMeetingPersistence()
    let storageRepository = InMemoryMeetingAudioStoragePersistence()
    let recorder = StubRecordingStarter()
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: meetingRepository,
        audioStorageRepository: storageRepository,
        retentionPolicyProvider: { .never },
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    _ = try service.startRecording(
        detectionSource: .auto,
        appBundleID: "com.microsoft.teams2",
        suggestedTitle: "Planning",
        pid: 42
    )

    #expect(storageRepository.storages.first?.retentionPolicy == MeetingAudioStorage.RetentionPolicy.never.rawValue)
}

@MainActor
@Test func recordingServiceWritesAndCompletesRecoveryMetadata() throws {
    let meetingRepository = InMemoryMeetingPersistence()
    let storageRepository = InMemoryMeetingAudioStoragePersistence()
    let rootFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("NexusMeetingMetadataTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: rootFolder) }

    var clock = Date(timeIntervalSince1970: 1_700_000_000)
    let recorder = StubRecordingStarter(rootFolder: rootFolder)
    let metadataStore = RecordingMetadataStore()
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: meetingRepository,
        audioStorageRepository: storageRepository,
        metadataStore: metadataStore,
        now: { clock }
    )

    let payload = try service.startRecording(
        detectionSource: .auto,
        appBundleID: "com.microsoft.teams2",
        suggestedTitle: "Planning",
        pid: 42
    )
    let folder = URL(fileURLWithPath: payload.folderPath, isDirectory: true)
    let startedMetadata = try metadataStore.read(folder: folder)
    #expect(startedMetadata.id == payload.meetingID.uuidString)
    #expect(startedMetadata.title == "Planning")
    #expect(startedMetadata.startedAt == 1_700_000_000)
    #expect(startedMetadata.processingStatus == MeetingProcessingStatus.recording.rawValue)

    clock = Date(timeIntervalSince1970: 1_700_000_180)
    _ = try service.stopRecording(meetingID: payload.meetingID)

    let stoppedMetadata = try metadataStore.read(folder: folder)
    #expect(stoppedMetadata.durationSec == 180)
    #expect(stoppedMetadata.recordingCompletedAt == 1_700_000_180)
    #expect(stoppedMetadata.processingStatus == MeetingProcessingStatus.queued.rawValue)
}

@MainActor
@Test func recordingServicePausesAndResumesActiveRecorder() throws {
    let meetingID = UUID()
    let recorder = StubRecordingStarter(
        activeHandle: RecordingHandle(
            meetingID: meetingID,
            folder: URL(fileURLWithPath: "/tmp/\(meetingID.uuidString)")
        )
    )
    let service = MeetingRecordingService(
        recorder: recorder,
        meetingRepository: InMemoryMeetingPersistence(),
        audioStorageRepository: InMemoryMeetingAudioStoragePersistence()
    )

    try service.pauseRecording(meetingID: meetingID)
    #expect(recorder.pauseCallCount == 1)
    #expect(recorder.isPaused)

    try service.resumeRecording(meetingID: meetingID)
    #expect(recorder.resumeCallCount == 1)
    #expect(recorder.isPaused == false)
}

@MainActor
@Test func recordingServicePauseRejectsWhenIdleOrMismatched() throws {
    let activeID = UUID()
    let idleRecorder = StubRecordingStarter()
    let idleService = MeetingRecordingService(
        recorder: idleRecorder,
        meetingRepository: InMemoryMeetingPersistence(),
        audioStorageRepository: InMemoryMeetingAudioStoragePersistence()
    )
    #expect(throws: MeetingRecordingServiceError.recordingMissing) {
        try idleService.pauseRecording(meetingID: activeID)
    }
    #expect(idleRecorder.pauseCallCount == 0)

    let activeRecorder = StubRecordingStarter(
        activeHandle: RecordingHandle(
            meetingID: activeID,
            folder: URL(fileURLWithPath: "/tmp/\(activeID.uuidString)")
        )
    )
    let activeService = MeetingRecordingService(
        recorder: activeRecorder,
        meetingRepository: InMemoryMeetingPersistence(),
        audioStorageRepository: InMemoryMeetingAudioStoragePersistence()
    )
    #expect(throws: MeetingRecordingServiceError.recordingMismatch) {
        try activeService.resumeRecording(meetingID: UUID())
    }
    #expect(activeRecorder.resumeCallCount == 0)
}

@MainActor
private final class InMemoryMeetingPersistence: MeetingPersisting {
    var meetings: [Meeting] = []

    func insert(_ meeting: Meeting) throws {
        meetings.append(meeting)
    }

    func upsert(_ meeting: Meeting) throws {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else {
            meetings.append(meeting)
            return
        }
        meetings[index] = meeting
    }

    func find(id: UUID) throws -> Meeting? {
        meetings.first { $0.id == id }
    }

    func delete(id: UUID) throws {
        meetings.removeAll { $0.id == id }
    }
}

@MainActor
private final class InMemoryMeetingAudioStoragePersistence: MeetingAudioStoragePersisting {
    var storages: [MeetingAudioStorage] = []
    let insertError: Error?

    init(insertError: Error? = nil) {
        self.insertError = insertError
    }

    func insert(_ storage: MeetingAudioStorage) throws {
        if let insertError {
            throw insertError
        }
        storages.append(storage)
    }

    func find(meetingID: UUID) throws -> MeetingAudioStorage? {
        storages.first { $0.meetingID == meetingID }
    }
}

@MainActor
private final class StubRecordingStarter: MeetingRecordingStarting {
    let startError: Error?
    var stopCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var isPaused = false
    var startedFolder: URL?
    private let rootFolder: URL?
    private var handle: RecordingHandle?

    init(startError: Error? = nil, rootFolder: URL? = nil, activeHandle: RecordingHandle? = nil) {
        self.startError = startError
        self.rootFolder = rootFolder
        handle = activeHandle
        startedFolder = activeHandle?.folder
    }

    func start(meetingID: UUID, pid: pid_t) throws -> RecordingHandle {
        if let startError {
            throw startError
        }
        let folder =
            rootFolder?.appendingPathComponent(meetingID.uuidString, isDirectory: true)
            ?? URL(fileURLWithPath: "/tmp/\(meetingID.uuidString)")
        if rootFolder != nil {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let handle = RecordingHandle(
            meetingID: meetingID,
            folder: folder
        )
        startedFolder = folder
        self.handle = handle
        return handle
    }

    func stop() throws {
        stopCallCount += 1
        handle = nil
    }

    func pause() throws {
        pauseCallCount += 1
        isPaused = true
    }

    func resume() throws {
        resumeCallCount += 1
        isPaused = false
    }

    func currentHandle() -> RecordingHandle? {
        handle
    }
}

private enum RecordingServiceTestError: Error, Equatable {
    case startFailed
    case storageFailed
}
