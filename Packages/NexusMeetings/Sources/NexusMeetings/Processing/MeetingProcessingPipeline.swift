import Foundation
import NexusAI
import NexusCore

@MainActor
public final class MeetingProcessingPipeline {
    private let repo: MeetingRepository
    private let vad: VADTrimStage
    private let transcription: TranscriptionStage
    private let diarization: DiarizationStage
    private let merge: MergeStage
    private let summary: SummaryStage
    private let actionItems: ActionItemsStage
    private let providerProfile: @MainActor () -> String
    private let customSummaryTemplateProvider: @MainActor () -> String?
    private let summaryProviderPreference: @MainActor () -> MeetingsSummaryProviderPreference
    private let customVocabularyProvider: @MainActor () -> [CustomVocabularyEntry]
    private let metadataStore: RecordingMetadataStore
    private let screenContextStore: ScreenContextStore
    private let now: @MainActor () -> Date

    public init(
        repo: MeetingRepository,
        vad: VADTrimStage,
        transcription: TranscriptionStage,
        diarization: DiarizationStage,
        merge: MergeStage,
        summary: SummaryStage,
        actionItems: ActionItemsStage,
        providerProfile: @escaping @MainActor () -> String,
        customSummaryTemplateProvider: @escaping @MainActor () -> String? = {
            MeetingsPromptStore.shared.load()
        },
        summaryProviderPreference: @escaping @MainActor () -> MeetingsSummaryProviderPreference = {
            MeetingsProviderSettingsStore.shared.summaryProvider()
        },
        customVocabularyProvider: @escaping @MainActor () -> [CustomVocabularyEntry] = {
            UserDefaultsCustomVocabularyStore.shared.load()
        },
        metadataStore: RecordingMetadataStore = RecordingMetadataStore(),
        screenContextStore: ScreenContextStore = ScreenContextStore(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.repo = repo
        self.vad = vad
        self.transcription = transcription
        self.diarization = diarization
        self.merge = merge
        self.summary = summary
        self.actionItems = actionItems
        self.providerProfile = providerProfile
        self.customSummaryTemplateProvider = customSummaryTemplateProvider
        self.summaryProviderPreference = summaryProviderPreference
        self.customVocabularyProvider = customVocabularyProvider
        self.metadataStore = metadataStore
        self.screenContextStore = screenContextStore
        self.now = now
    }

    public func process(meeting: Meeting, audioFolder: URL) async throws {
        let meURL = audioFolder.appendingPathComponent("me.wav")
        let othersURL = audioFolder.appendingPathComponent("others.wav")
        let durationMs = max(0, meeting.durationSec) * 1_000
        var currentStage = MeetingProcessingStatus.processingVAD.rawValue

        do {
            // Each `setStatus` first runs `try Task.checkCancellation()`, so
            // cancellation (see `PipelineQueue.cancelProcessing`) is observed at
            // every stage boundary: a cancelled run falls into the `catch` and is
            // recorded as failed-at-stage, so it can be reprocessed from there.
            try setStatus(meeting, .processingVAD)
            _ = try await vad.run(audioURL: meURL, durationMs: durationMs)
            _ = try await vad.run(audioURL: othersURL, durationMs: durationMs)

            currentStage = MeetingProcessingStatus.processingASR.rawValue
            try setStatus(meeting, .processingASR)
            let transcriptionOutput = try await transcription.run(
                meURL: meURL,
                othersURL: othersURL,
                languageHint: meeting.languageCode
            )
            meeting.languageCode = transcriptionOutput.detectedLanguage

            currentStage = MeetingProcessingStatus.processingDiarization.rawValue
            try setStatus(meeting, .processingDiarization)
            let diarizationOutput = try await diarization.run(audioURL: othersURL)

            currentStage = MeetingProcessingStatus.processingMerge.rawValue
            try setStatus(meeting, .processingMerge)
            try mergeAndPersistTranscript(
                meeting: meeting,
                transcription: transcriptionOutput,
                diarization: diarizationOutput,
                audioFolder: audioFolder
            )

            // Screen-OCR context (spec §7): recording-time OCR text bridged via a
            // text-only sidecar in the audio folder (no schema field). `nil` when
            // the opt-in feature was off, so the prompts are byte-unchanged.
            let screenContext = screenContextStore.combinedText(folder: audioFolder)

            currentStage = MeetingProcessingStatus.processingSummary.rawValue
            try setStatus(meeting, .processingSummary)
            meeting.summaryText = try await summary.run(
                transcript: meeting.transcriptText,
                title: meeting.title,
                durationSec: meeting.durationSec,
                customTemplate: customSummaryTemplateProvider(),
                providerPreference: summaryProviderPreference(),
                screenContext: screenContext
            )

            currentStage = MeetingProcessingStatus.processingActions.rawValue
            try setStatus(meeting, .processingActions)
            _ = try await actionItems.run(
                meeting: meeting,
                transcript: meeting.transcriptText,
                summary: meeting.summaryText,
                screenContext: screenContext
            )

            let stamp = now()
            meeting.providerProfile = Self.providerProfile(
                transcriptionProfile: transcriptionOutput.providerProfile,
                diarizationProfile: providerProfile()
            )
            meeting.processingStatus = MeetingProcessingStatus.ready.rawValue
            meeting.processedAt = stamp
            meeting.updatedAt = stamp
            try repo.upsert(meeting)
            try metadataStore.markProcessed(meeting: meeting, folder: audioFolder, processedAt: stamp)
        } catch {
            try? setFailureStatus(meeting, stage: currentStage)
            throw error
        }
    }

    /// Merges the transcription + diarization into speaker segments, applies the
    /// deterministic custom-vocabulary correction to the segments, then renders
    /// the transcript from the corrected segments — so `segmentsJSON`,
    /// `transcriptText`, and the downstream summary/action-items all share the
    /// canonical spelling (spec §8). Empty vocabulary is an identity pass.
    private func mergeAndPersistTranscript(
        meeting: Meeting,
        transcription: TranscriptionStageOutput,
        diarization: [DiarizationSegment],
        audioFolder: URL
    ) throws {
        let mergedSegments = merge.merge(
            me: transcription.me,
            others: transcription.others,
            othersDiarization: diarization
        )
        let segments = CustomVocabularyReplacer(customVocabularyProvider()).apply(to: mergedSegments)
        meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
        meeting.transcriptText = merge.renderLinear(segments)
        try metadataStore.markTranscriptComplete(meeting: meeting, folder: audioFolder, completedAt: now())
    }

    private func setStatus(_ meeting: Meeting, _ status: MeetingProcessingStatus) throws {
        // Stage boundary: observe cooperative cancellation before entering the
        // next (potentially long) stage.
        try Task.checkCancellation()
        meeting.processingStatus = status.rawValue
        meeting.updatedAt = now()
        try repo.updateProcessingStatus(status.rawValue, for: meeting.id)
    }

    private func setFailureStatus(_ meeting: Meeting, stage: String) throws {
        let failedStatus = MeetingProcessingStatus.failedAt(stage: stage)
        meeting.processingStatus = failedStatus
        meeting.updatedAt = now()
        try repo.updateProcessingStatus(failedStatus, for: meeting.id)
    }

    private static func providerProfile(
        transcriptionProfile: String,
        diarizationProfile: String
    ) -> String {
        let suffix = "+sortformer"
        if diarizationProfile.hasSuffix(suffix) {
            return "\(transcriptionProfile)\(suffix)"
        }
        return transcriptionProfile
    }
}

extension MeetingProcessingPipeline {
    public static func stubbed(
        repo: MeetingRepository,
        finalProviderProfile: String
    ) -> MeetingProcessingPipeline {
        let provider = NoopMeetingTranscriptionProvider()
        let router = NoopMeetingProcessingRouter()
        return MeetingProcessingPipeline(
            repo: repo,
            vad: VADTrimStage(sileroLoader: { NoopSileroVADSession() }),
            transcription: TranscriptionStage(primary: provider, fallback: provider),
            diarization: DiarizationStage(sessionLoader: { NoopSortformerSession() }),
            merge: MergeStage(),
            summary: SummaryStage(router: router),
            actionItems: ActionItemsStage(
                router: router,
                taskRepository: TaskItemRepository(
                    context: repo.context,
                    scheduler: RRuleScheduler(),
                    now: Date.init
                ),
                meetingRepository: repo,
                linkRepository: LinkRepository(context: repo.context),
                sourceID: "meetings.action-items"
            ),
            providerProfile: { finalProviderProfile }
        )
    }
}

private struct NoopMeetingTranscriptionProvider: MeetingTranscriptionProvider {
    let identifier = "noop"

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", segments: [], detectedLanguage: languageHint ?? "und")
    }
}

private struct NoopSileroVADSession: SileroVADSession {
    func detectSpeechRanges(audioURL: URL, durationMs: Int) async throws -> [VADSpeechRange] {
        guard durationMs > 0 else { return [] }
        return [VADSpeechRange(startMs: 0, endMs: durationMs)]
    }
}

private struct NoopSortformerSession: SortformerSession {
    func diarize(audioURL: URL) async throws -> [DiarizationSegment] {
        []
    }
}

private struct NoopMeetingProcessingRouter: MeetingProcessingRouting {
    func route(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "[]", providerUsed: .appleIntelligence)
    }
}
