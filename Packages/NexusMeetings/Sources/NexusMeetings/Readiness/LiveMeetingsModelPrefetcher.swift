import FluidAudio
import Foundation
import NexusAI

/// Downloads the three meeting models on demand, mirroring the exact load/download
/// entry points the processing pipeline uses so a prefetch warms the same on-disk
/// cache the providers later read.
///
/// Lives in the shared module (not the helper) so the **main app** can drive
/// downloads in-process — it has `network.client` and needs no sandboxed helper.
///
/// - parakeet / sortformer: FluidAudio's `downloadAndLoad` / `loadFromHuggingFace`
///   stream real fractional progress via `DownloadUtils.ProgressHandler`.
/// - whisperKit: routed through ``WhisperKitModelDownloadCoordinator`` (the same
///   path Settings uses). That coordinator exposes only an observable `phase`, no
///   fractional callback, so progress is reported best-effort (1.0 on success) and
///   failure is surfaced by inspecting the terminal phase.
public struct LiveMeetingsModelPrefetcher: MeetingsModelPrefetching {
    public init() {}

    public func prefetch(_ id: MeetingsModelID, progress: @Sendable @escaping (Double) -> Void) async throws {
        switch id {
        case .parakeet:
            _ = try await AsrModels.downloadAndLoad(
                version: .v3,
                encoderPrecision: .int8,
                progressHandler: { downloadProgress in
                    progress(downloadProgress.fractionCompleted)
                }
            )
        case .sortformer:
            _ = try await SortformerModels.loadFromHuggingFace(
                config: .default,
                progressHandler: { downloadProgress in
                    progress(downloadProgress.fractionCompleted)
                }
            )
        case .whisperKit:
            try await prefetchWhisperKit(progress: progress)
        }
    }

    private func prefetchWhisperKit(progress: @Sendable @escaping (Double) -> Void) async throws {
        let coordinator = await MainActor.run { WhisperKitModelDownloadCoordinator() }
        await coordinator.download()
        let phase = await MainActor.run { coordinator.phase }
        switch phase {
        case .done:
            progress(1.0)
        case .failed(let reason):
            throw MeetingsModelPrefetchError.whisperKitDownloadFailed(reason)
        default:
            // `download()` only returns on a terminal phase; any non-terminal
            // phase here means the download never ran (e.g. a concurrent call
            // was in flight). Treat as a failure so the snapshot doesn't claim
            // readiness the disk can't back.
            throw MeetingsModelPrefetchError.whisperKitDownloadFailed("Download did not complete.")
        }
    }
}

public enum MeetingsModelPrefetchError: Error {
    case whisperKitDownloadFailed(String)
}
