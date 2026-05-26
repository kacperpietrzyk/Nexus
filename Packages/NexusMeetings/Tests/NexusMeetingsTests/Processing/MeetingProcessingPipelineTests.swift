import Foundation
import NexusAI
import NexusCore
import Testing

@testable import NexusMeetings

@MainActor
@Test func pipelineUpdatesProcessingStatusAcrossStages() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting(status: .queued)
    try meetingRepo.insert(meeting)

    let pipeline = MeetingProcessingPipeline.stubbed(
        repo: meetingRepo,
        finalProviderProfile: "stub-provider"
    )
    try await pipeline.process(meeting: meeting, audioFolder: URL(fileURLWithPath: "/tmp/x"))

    let updated = try #require(try meetingRepo.find(id: meeting.id))
    #expect(updated.processingStatus == MeetingProcessingStatus.ready.rawValue)
    #expect(updated.providerProfile == "noop")
    #expect(updated.processedAt != nil)
    #expect(try MeetingSpeakerSegment.decode(updated.segmentsJSON).isEmpty)
}

@MainActor
@Test func pipelinePersistsFallbackTranscriptionProviderProfile() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting(status: .queued)
    try meetingRepo.insert(meeting)
    let router = StaticMeetingProcessingRouter()
    let pipeline = MeetingProcessingPipeline(
        repo: meetingRepo,
        vad: VADTrimStage(sileroLoader: { TestNoopVADSession() }),
        transcription: TranscriptionStage(
            primary: EmptyTranscriptionProvider(identifier: "parakeet"),
            fallback: TextTranscriptionProvider(identifier: "whisperkit")
        ),
        diarization: DiarizationStage(sessionLoader: { TestNoopSortformerSession() }),
        merge: MergeStage(),
        summary: SummaryStage(router: router),
        actionItems: ActionItemsStage(
            router: router,
            taskRepository: TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: Date.init
            ),
            meetingRepository: meetingRepo,
            linkRepository: LinkRepository(context: context),
            sourceID: "meetings.action-items"
        ),
        providerProfile: { "parakeet+sortformer" }
    )

    let audioFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("pipeline-provider-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: audioFolder) }
    try await pipeline.process(meeting: meeting, audioFolder: audioFolder)

    let updated = try #require(try meetingRepo.find(id: meeting.id))
    #expect(updated.providerProfile == "whisperkit+sortformer")
    let metadata = try RecordingMetadataStore().read(folder: audioFolder)
    #expect(metadata.transcriptCompletedAt != nil)
    #expect(metadata.processedAt != nil)
}

@MainActor
@Test func pipelinePassesCustomSummaryTemplateAndProviderPreference() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting(title: "Daily", status: .queued)
    try meetingRepo.insert(meeting)
    let router = CapturingMeetingProcessingRouter()
    let pipeline = MeetingProcessingPipeline(
        repo: meetingRepo,
        vad: VADTrimStage(sileroLoader: { TestNoopVADSession() }),
        transcription: TranscriptionStage(
            primary: TextTranscriptionProvider(identifier: "parakeet-tdt-v3"),
            fallback: TextTranscriptionProvider(identifier: "whisperkit-large")
        ),
        diarization: DiarizationStage(sessionLoader: { TestNoopSortformerSession() }),
        merge: MergeStage(),
        summary: SummaryStage(router: router),
        actionItems: ActionItemsStage(
            router: router,
            taskRepository: TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: Date.init
            ),
            meetingRepository: meetingRepo,
            linkRepository: LinkRepository(context: context),
            sourceID: "meetings.action-items"
        ),
        providerProfile: { "parakeet-tdt-v3+sortformer" },
        customSummaryTemplateProvider: { "Custom {{title}} -> {{transcript}}" },
        summaryProviderPreference: { .auto }
    )

    let audioFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("pipeline-summary-settings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: audioFolder) }
    try await pipeline.process(meeting: meeting, audioFolder: audioFolder)

    let requests = await router.requests
    let summaryRequest = try #require(requests.first)
    #expect(summaryRequest.prompt.contains("Custom Daily ->"))
    #expect(summaryRequest.providerPreference == .auto)
}

@MainActor
@Test func pipelinePersistsFailureStatusAndRethrowsStageError() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting(status: .queued)
    try meetingRepo.insert(meeting)

    let router = StaticMeetingProcessingRouter()
    let pipeline = MeetingProcessingPipeline(
        repo: meetingRepo,
        vad: VADTrimStage(sileroLoader: { TestNoopVADSession() }),
        transcription: TranscriptionStage(
            primary: ThrowingTranscriptionProvider(),
            fallback: ThrowingTranscriptionProvider()
        ),
        diarization: DiarizationStage(sessionLoader: { TestNoopSortformerSession() }),
        merge: MergeStage(),
        summary: SummaryStage(router: router),
        actionItems: ActionItemsStage(
            router: router,
            taskRepository: TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: Date.init
            ),
            meetingRepository: meetingRepo,
            linkRepository: LinkRepository(context: context),
            sourceID: "meetings.action-items"
        ),
        providerProfile: { "never-used" }
    )

    do {
        try await pipeline.process(meeting: meeting, audioFolder: URL(fileURLWithPath: "/tmp/x"))
        Issue.record("Expected ASR failure to be rethrown")
    } catch PipelineTestError.asr {
        let updated = try #require(try meetingRepo.find(id: meeting.id))
        #expect(
            updated.processingStatus
                == MeetingProcessingStatus.failedAt(stage: MeetingProcessingStatus.processingASR.rawValue)
        )
    } catch {
        Issue.record("Expected ASR failure, got \(error)")
    }
}

private enum PipelineTestError: Error {
    case asr
}

private struct ThrowingTranscriptionProvider: MeetingTranscriptionProvider {
    let identifier = "throwing"

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        throw PipelineTestError.asr
    }
}

private struct EmptyTranscriptionProvider: MeetingTranscriptionProvider {
    let identifier: String

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", segments: [], detectedLanguage: "und")
    }
}

private struct TextTranscriptionProvider: MeetingTranscriptionProvider {
    let identifier: String

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "hello from \(identifier)",
            segments: [
                TranscriptionSegment(
                    startMs: 0,
                    endMs: 1_000,
                    text: "hello from \(identifier)"
                )
            ],
            detectedLanguage: "en"
        )
    }
}

private struct TestNoopVADSession: SileroVADSession {
    func detectSpeechRanges(audioURL: URL, durationMs: Int) async throws -> [VADSpeechRange] {
        guard durationMs > 0 else { return [] }
        return [VADSpeechRange(startMs: 0, endMs: durationMs)]
    }
}

private struct TestNoopSortformerSession: SortformerSession {
    func diarize(audioURL: URL) async throws -> [DiarizationSegment] {
        []
    }
}

private struct StaticMeetingProcessingRouter: MeetingProcessingRouting {
    func route(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "[]", providerUsed: .appleIntelligence)
    }
}

private actor CapturingMeetingProcessingRouter: MeetingProcessingRouting {
    private(set) var requests: [AIRequest] = []

    func route(_ request: AIRequest) async throws -> AIResponse {
        requests.append(request)
        return AIResponse(text: "[]", providerUsed: .appleIntelligence)
    }
}
