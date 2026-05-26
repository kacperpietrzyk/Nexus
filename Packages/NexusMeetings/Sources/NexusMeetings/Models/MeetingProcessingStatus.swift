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
}
