import Foundation
import NexusAI
import NexusCore
import NexusMeetings
import NexusSync
import SwiftData
import TasksFeature

@MainActor
final class HelperComposition {
    let container: ModelContainer
    let context: ModelContext
    let meetingsComposition: MeetingsComposition
    let statusBar: StatusBarController
    let xpcService: MeetingsHelperXPCService
    let readinessCoordinator: HelperReadinessCoordinator
    let meetingProcessor: MeetingSummaryDeferralProcessor
    let summaryFallbackScheduler: SummaryFallbackScheduler

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
            dateExtractor: NLParserDateExtractor(),
            workspaceProvider: NSWorkspaceProvider(),
            recorder: recorder,
            appPatternRegistry: patternStore.load(),
            appPatternRegistryProvider: { patternStore.load() }
        )
        meetingsComposition.registerInboxSource()

        let (scheduler, processor) = Self.makeDeferralProcessor(composition: meetingsComposition)
        summaryFallbackScheduler = scheduler
        meetingProcessor = processor

        statusBar = StatusBarController()
        xpcDelegate = MeetingsHelperXPCDelegate(
            recorder: meetingsComposition.recorder,
            pipeline: meetingsComposition.pipeline,
            pipelineQueue: meetingsComposition.pipelineQueue,
            meetingRepository: meetingsComposition.meetingRepository,
            audioStorageRepository: meetingsComposition.audioStorageRepository,
            meetingProcessor: processor,
            retentionPolicyProvider: { retentionStore.load() }
        )
        xpcService = MeetingsHelperXPCService(delegate: xpcDelegate)
        readinessCoordinator = Self.makeReadinessCoordinator()
        try recoverInterruptedRecordings(rootFolder: rootFolder)
        xpcService.resume()
    }

    private static func makeReadinessCoordinator() -> HelperReadinessCoordinator {
        HelperReadinessCoordinator(
            computer: MeetingsReadinessFactory.makeComputer(),
            store: UserDefaultsMeetingsReadinessStore.shared,
            prefetcher: LiveMeetingsModelPrefetcher()
        )
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

    func pauseRecording(meetingID: UUID, reply: @escaping (Error?) -> Void) {
        xpcDelegate.pauseRecording(meetingID: meetingID.uuidString as NSString, reply: reply)
    }

    func resumeRecording(meetingID: UUID, reply: @escaping (Error?) -> Void) {
        xpcDelegate.resumeRecording(meetingID: meetingID.uuidString as NSString, reply: reply)
    }

    func currentRecordingState() -> RecordingStateSnapshot {
        xpcDelegate.recordingStateSnapshot()
    }

    private static func makeDeferralProcessor(
        composition: MeetingsComposition
    ) -> (SummaryFallbackScheduler, MeetingSummaryDeferralProcessor) {
        let pipeline = composition.pipeline
        let repo = composition.meetingRepository
        let scheduler = SummaryFallbackScheduler(
            status: { (try? repo.find(id: $0))?.processingStatus },
            run: { meetingID, folder in
                guard let meeting = try? repo.find(id: meetingID) else { return }
                try? await pipeline.processSummaryAndActions(meeting: meeting, audioFolder: folder)
            }
        )
        let processor = MeetingSummaryDeferralProcessor(
            transcribe: { try await pipeline.processTranscriptionOnly(meeting: $0, audioFolder: $1) },
            summarize: { try await pipeline.processSummaryAndActions(meeting: $0, audioFolder: $1) },
            preference: { MeetingsProviderSettingsStore.shared.summaryProvider() },
            markAwaiting: { meeting in
                meeting.processingStatus = MeetingProcessingStatus.awaitingExternalSummary.rawValue
                meeting.updatedAt = Date()
                try? repo.upsert(meeting)
            },
            postNeedsSummary: { MeetingSummaryHandoffNotification.post(meetingID: $0, folderPath: $1) },
            scheduleFallback: { scheduler.schedule(meetingID: $0, audioFolder: $1) }
        )
        return (scheduler, processor)
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
            let meetingID = candidate.meetingID
            Task {
                await meetingsComposition.pipelineQueue.enqueue(meetingID: meetingID) { [meetingProcessor] in
                    await meetingProcessor.process(meeting: meeting, audioFolder: audioFolder)
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
