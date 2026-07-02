import Foundation

public enum MeetingProcessingStatus: String, Sendable, Codable, CaseIterable {
    case recording
    case queued
    case processingVAD = "processing-vad"
    case processingASR = "processing-asr"
    case processingDiarization = "processing-diarization"
    case processingMerge = "processing-merge"
    case processingSummary = "processing-summary"
    case processingActions = "processing-actions"
    case awaitingExternalSummary = "awaiting-external-summary"
    case claimedExternalSummary = "claimed-external-summary"
    case ready
    case failed

    public static func failedAt(stage: String) -> String { "failed:\(stage)" }

    public static func isFailed(_ raw: String) -> Bool {
        raw.hasPrefix("failed:") || raw == failed.rawValue
    }

    public static func failureStage(of raw: String) -> String? {
        guard raw.hasPrefix("failed:") else { return nil }
        return String(raw.dropFirst("failed:".count))
    }

    /// True while the helper is actively working a meeting's pipeline (queued
    /// or any `processing-*` stage) — i.e. a cancellable in-flight job. Used to
    /// gate the in-app "Cancel processing" control, which drives the helper's
    /// `PipelineQueue` over XPC.
    public static func isInFlight(_ raw: String) -> Bool {
        raw == queued.rawValue || raw.hasPrefix("processing-")
    }

    /// True once transcription has finished: only the summary/action-items remain
    /// pending, or the meeting is fully done. Such a meeting must NOT be re-run
    /// through the full pipeline on crash recovery — re-transcribing discards the
    /// finished transcript (and can double-materialize action-item tasks).
    public static func transcriptComplete(_ raw: String) -> Bool {
        switch raw {
        case processingSummary.rawValue, processingActions.rawValue,
            awaitingExternalSummary.rawValue, claimedExternalSummary.rawValue,
            ready.rawValue:
            true
        default:
            false
        }
    }

    /// Transcript done but the deferred (assistant-model) summary is still pending
    /// — safe to re-arm the handoff + fallback on crash recovery WITHOUT
    /// re-transcribing.
    public static func awaitingSummary(_ raw: String) -> Bool {
        raw == awaitingExternalSummary.rawValue || raw == claimedExternalSummary.rawValue
    }
}
