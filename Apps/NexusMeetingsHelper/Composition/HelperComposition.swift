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

    /// Age past which a `claimedExternalSummary` meeting is treated as orphaned and
    /// reclaimed on helper relaunch. Generous by design: the app's OWN launch sweep
    /// reclaims instantly on app restart, so a long threshold only delays the rare
    /// app-died-and-never-reopens case; too short risks reclaiming a live-but-backlogged
    /// claim — the very double-summary bug this gate exists to prevent.
    private static let claimStalenessThreshold: TimeInterval = 30 * 60

    init() throws {
        let patternStore = UserDefaultsAppPatternRegistryStore.shared
        let retentionStore = UserDefaultsMeetingRetentionPolicyStore.shared
        appPatternRegistryStore = patternStore
        retentionPolicyStore = retentionStore

        // The helper bundle carries NO iCloud entitlements (only the App Group), so it
        // MUST NOT stand up a CloudKit mirror — doing so traps on launch (SIGTRAP in
        // NSCloudKitMirroringDelegate setup) and crash-loops the helper, killing both
        // auto-detection and the manual-record XPC endpoint. The main app owns the single
        // mirror and exports the helper's writes via persistent-history on the shared store.
        container = try NexusModelContainer.make(
            groupContainerIdentifier: NexusModelContainer.appGroupIdentifier,
            extraModels: MeetingsComposition.extraModels,
            localOnlyExtraModels: MeetingsComposition.localOnlyExtraModels,
            forceLocalOnly: true
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
            appPatternRegistryProvider: { patternStore.load() },
            // The helper runs the FULL pipeline including on-device ASR. When the
            // watchdog abandons a hung transcription, the queue must reset the
            // Parakeet/WhisperKit engines (the zombie ignores cancellation and keeps
            // holding the ANE/GPU) — the composition wires that reset from the
            // providers it owns.
            recoversASREngines: true
        )
        meetingsComposition.registerInboxSource()

        let (scheduler, processor) = Self.makeDeferralProcessor(composition: meetingsComposition, container: container)
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

    /// Installs the AppDelegate's UI presenter for any successful recording start
    /// (detection- or app-initiated), so both paths show the Stop/Pause panel.
    func setRecordingStartedHandler(_ handler: @escaping @MainActor (MeetingHandlePayload, String) -> Void) {
        xpcDelegate.onRecordingStarted = handler
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
        composition: MeetingsComposition,
        container: ModelContainer
    ) -> (SummaryFallbackScheduler, MeetingSummaryDeferralProcessor) {
        let pipeline = composition.pipeline
        let repo = composition.meetingRepository
        let scheduler = SummaryFallbackScheduler(
            status: { meetingID in
                let fresh = ModelContext(container)
                let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
                return (try? fresh.fetch(descriptor))?.first?.processingStatus
            },
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
            // A meeting whose transcript is already complete must NOT be re-run
            // through the full pipeline: re-transcription discards the finished
            // transcript, and if the main app already claimed the summary both
            // processes materialize duplicate action-item tasks. `CrashRecovery`
            // gates only on metadata `processedAt == nil`, which is written AFTER
            // the `.ready` status is committed — so the authoritative store status
            // is the correct gate here.
            if let existing = try meetingsComposition.meetingRepository.find(id: candidate.meetingID) {
                let status = existing.processingStatus
                if SummaryClaimDecision.shouldReclaimOnHelperLaunch(
                    status: status,
                    claimedAt: existing.claimedAt,
                    now: Date(),
                    staleness: Self.claimStalenessThreshold
                ) {
                    // Transcript done, deferred summary still pending. Re-arm the
                    // external-summary handoff + fallback (NO re-transcription): a
                    // running app re-claims it, otherwise the helper summarizes once
                    // the fallback timeout elapses. A RECENT `claimedExternalSummary`
                    // is excluded by the staleness gate — a live app session owns it
                    // and must not be reset (would cause a double summary); the
                    // `transcriptComplete` branch below then leaves it untouched.
                    rearmDeferredSummary(existing, audioFolder: candidate.audioFolder)
                    continue
                }
                if MeetingProcessingStatus.transcriptComplete(status) {
                    // `.ready`, or a summary stage already committed/in-flight —
                    // nothing to recover, and re-running would overwrite good output.
                    continue
                }
            }

            // Genuinely incomplete (never persisted, still recording/queued, or
            // interrupted mid-transcription) → (re)hydrate and run the full pipeline.
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

    /// Re-arms a transcript-complete meeting's deferred (assistant-model) summary
    /// after a helper relaunch, without re-transcribing. Resets a stale
    /// `claimedExternalSummary` (owned by a previous app session that died) back to
    /// awaiting so the app can re-claim it, re-posts the handoff, and re-schedules
    /// the local fallback in case the app never comes up.
    private func rearmDeferredSummary(_ meeting: Meeting, audioFolder: URL) {
        meeting.processingStatus = MeetingProcessingStatus.awaitingExternalSummary.rawValue
        meeting.updatedAt = Date()
        try? meetingsComposition.meetingRepository.upsert(meeting)
        MeetingSummaryHandoffNotification.post(meetingID: meeting.id, folderPath: audioFolder.path)
        summaryFallbackScheduler.schedule(meetingID: meeting.id, audioFolder: audioFolder)
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
