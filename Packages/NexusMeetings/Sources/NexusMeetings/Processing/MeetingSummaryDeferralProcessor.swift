import Foundation

/// Meeting processing policy used by the recorder host (the helper). Always
/// transcribes locally, then:
/// - `.assistantModel`: mark the meeting awaiting, notify the main app (which
///   owns Gemma), and arm a fallback timer.
/// - `.appleIntelligence` / `.disabled`: run the summary/action-items
///   continuation in-process immediately.
/// Side effects are injected so the decision logic is testable without a real
/// pipeline, repository, or notification center.
@MainActor
public final class MeetingSummaryDeferralProcessor {
    public typealias Stage = @MainActor (Meeting, URL) async throws -> Void

    private let transcribe: Stage
    private let summarize: Stage
    private let preference: @MainActor () -> MeetingsSummaryProviderPreference
    private let markAwaiting: @MainActor (Meeting) -> Void
    private let postNeedsSummary: @MainActor (UUID, String) -> Void
    private let scheduleFallback: @MainActor (UUID, URL) -> Void

    public init(
        transcribe: @escaping Stage,
        summarize: @escaping Stage,
        preference: @escaping @MainActor () -> MeetingsSummaryProviderPreference,
        markAwaiting: @escaping @MainActor (Meeting) -> Void,
        postNeedsSummary: @escaping @MainActor (UUID, String) -> Void,
        scheduleFallback: @escaping @MainActor (UUID, URL) -> Void
    ) {
        self.transcribe = transcribe
        self.summarize = summarize
        self.preference = preference
        self.markAwaiting = markAwaiting
        self.postNeedsSummary = postNeedsSummary
        self.scheduleFallback = scheduleFallback
    }

    public func process(meeting: Meeting, audioFolder: URL) async {
        do {
            try await transcribe(meeting, audioFolder)
        } catch {
            return  // failure status already recorded by the pipeline
        }

        if preference() == .assistantModel {
            markAwaiting(meeting)
            postNeedsSummary(meeting.id, audioFolder.path)
            scheduleFallback(meeting.id, audioFolder)
        } else {
            try? await summarize(meeting, audioFolder)
        }
    }
}
