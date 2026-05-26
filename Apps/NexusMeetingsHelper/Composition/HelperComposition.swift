import Foundation
import NexusAI
import NexusCore
import NexusMeetings
import NexusSync
import SwiftData

@MainActor
final class HelperComposition {
    let container: ModelContainer
    let context: ModelContext
    let meetingsComposition: MeetingsComposition
    let statusBar: StatusBarController
    let xpcService: MeetingsHelperXPCService

    private let xpcDelegate: MeetingsHelperXPCDelegate
    private let appPatternRegistryStore: UserDefaultsAppPatternRegistryStore
    private let retentionPolicyStore: UserDefaultsMeetingRetentionPolicyStore

    init() throws {
        let patternStore = UserDefaultsAppPatternRegistryStore.shared
        let retentionStore = UserDefaultsMeetingRetentionPolicyStore.shared
        appPatternRegistryStore = patternStore
        retentionPolicyStore = retentionStore

        container = try NexusModelContainer.make(
            groupContainerIdentifier: NexusModelContainer.appGroupIdentifier,
            extraModels: MeetingsComposition.extraModels,
            localOnlyExtraModels: MeetingsComposition.localOnlyExtraModels
        )
        context = ModelContext(container)

        let router = AIComposition.makeRouter(container: container)
        let rootFolder = Self.rootAudioFolder()
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let calendarProvider: any CalendarEventProviding = EventKitCalendarProvider.shared
        let recorder = MeetingRecorder(rootFolder: rootFolder)
        meetingsComposition = try MeetingsComposition(
            context: context,
            router: router,
            rootAudioFolder: rootFolder,
            calendarProvider: calendarProvider,
            workspaceProvider: NSWorkspaceProvider(),
            recorder: recorder,
            appPatternRegistry: patternStore.load(),
            appPatternRegistryProvider: { patternStore.load() }
        )
        meetingsComposition.registerInboxSource()

        statusBar = StatusBarController()
        xpcDelegate = MeetingsHelperXPCDelegate(
            recorder: meetingsComposition.recorder,
            pipeline: meetingsComposition.pipeline,
            pipelineQueue: meetingsComposition.pipelineQueue,
            meetingRepository: meetingsComposition.meetingRepository,
            audioStorageRepository: meetingsComposition.audioStorageRepository,
            retentionPolicyProvider: { retentionStore.load() }
        )
        xpcService = MeetingsHelperXPCService(delegate: xpcDelegate)
        try recoverInterruptedRecordings(rootFolder: rootFolder)
        xpcService.resume()
    }

    func startRecording(
        from event: MeetingDetectionEvent,
        reply: @escaping (MeetingHandlePayload?, Error?) -> Void
    ) {
        xpcDelegate.startRecording(
            detectionSource: MeetingDetectionSource.auto.rawValue,
            appBundleID: event.bundleID,
            suggestedTitle: event.suggestedTitle,
            pid: event.pid ?? 0,
            reply: reply
        )
    }

    func stopRecording(meetingID: UUID, reply: @escaping (Error?) -> Void) {
        xpcDelegate.stopRecording(meetingID: meetingID.uuidString as NSString, reply: reply)
    }

    func currentRecordingState() -> RecordingStateSnapshot {
        xpcDelegate.recordingStateSnapshot()
    }

    private static func rootAudioFolder() -> URL {
        MeetingAudioRootResolver.rootFolder()
    }

    private func recoverInterruptedRecordings(rootFolder: URL) throws {
        let candidates = try CrashRecovery(rootFolder: rootFolder).recover()
        for candidate in candidates {
            let meeting = try rehydrateMeeting(from: candidate)
            if try meetingsComposition.audioStorageRepository.find(meetingID: candidate.meetingID) == nil {
                try meetingsComposition.audioStorageRepository.insert(
                    MeetingAudioStorage(
                        meetingID: candidate.meetingID,
                        folderURL: candidate.audioFolder,
                        retentionPolicy: retentionPolicyStore.load()
                    )
                )
            }

            let audioFolder = candidate.audioFolder
            let pipeline = meetingsComposition.pipeline
            Task {
                await meetingsComposition.pipelineQueue.enqueue {
                    try? await pipeline.process(meeting: meeting, audioFolder: audioFolder)
                }
            }
        }
    }

    private func rehydrateMeeting(from candidate: RecoveredMeetingCandidate) throws -> Meeting {
        let endedAt = candidate.startedAt.addingTimeInterval(TimeInterval(candidate.durationSec))
        if let existing = try meetingsComposition.meetingRepository.find(id: candidate.meetingID) {
            guard existing.processingStatus != MeetingProcessingStatus.ready.rawValue else {
                return existing
            }
            existing.title = candidate.title
            existing.startedAt = candidate.startedAt
            existing.durationSec = candidate.durationSec
            existing.endedAt = endedAt
            existing.processingStatus = MeetingProcessingStatus.queued.rawValue
            try meetingsComposition.meetingRepository.upsert(existing)
            return existing
        }

        let meeting = Meeting(
            id: candidate.meetingID,
            title: candidate.title,
            startedAt: candidate.startedAt,
            durationSec: candidate.durationSec,
            endedAt: endedAt,
            detectionSource: .auto,
            processingStatus: .queued
        )
        try meetingsComposition.meetingRepository.insert(meeting)
        return meeting
    }
}
